import ArgumentParser
import AIDashCore
import Foundation

/// `aidash card put` — create or update a card within a container.
///
/// See `specs/001-core-briefing-cli/contracts/cli-surface.md` §"card put".
///
/// Flags (per contract):
///   --container-id <uuid>   required — parent container's UUID
///   --id <uuid>             required — this card's UUID (caller-supplied)
///   --type <CardType>       required — metric|insight|agentSummary|todoList|trending|digest|sectionHeader
///   --size <CardSize>       required — small|medium|wide|hero
///   --style <CardStyle>     required — neutral|success|warning|accent
///   --payload <json|@file>  required — inline JSON string, or `@/path/to/file.json`
///
/// Plus global `--json`/`--quiet` (declared on `GlobalOptions`).
///
/// Behavior:
///   1. Local validation via `SchemaValidator.validateCardPut`. Fail fast (exit 1)
///      with a `schema.*` envelope on stderr.
///   2. Build `CardPutParams` and dispatch via `XPCClient`.
///   3. On success: decode `CardPutResult`, emit via the active formatter.
///   4. On remote error (`ok=false` with error payload): emit the error envelope
///      on stderr with `response.requestId` and `Darwin.exit(3)` (MY-1455).
///   5. On malformed reply (`ok=false` without error): throw `xpc.decode_failure`
///      so the central handler maps to exit 2.
///
/// Exit codes:
///   0 — success
///   1 — local validation (`schema.*`, mapped centrally via `ExitCodeMapper`)
///   2 — XPC transport/decode (`xpc.*`, mapped centrally via `ExitCodeMapper`)
///   3 — remote error (emitted locally with `response.requestId` on stderr)
struct CardPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a card within a container."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .customLong("container-id"), help: "Parent container's UUID.")
    var containerId: String

    @Option(name: .long, help: "This card's UUID (caller-supplied).")
    var id: String

    @Option(name: .long, help: "Card type: metric | insight | agentSummary | todoList | trending | digest | sectionHeader.")
    var type: String

    @Option(name: .long, help: "Card size: small | medium | wide | hero.")
    var size: String

    @Option(name: .long, help: "Card style: neutral | success | warning | accent (default: neutral).")
    var style: String = CardStyle.neutral.rawValue

    @Option(
        name: .long,
        help: "Card payload as inline JSON string, or '@/path/to/file.json' to read from a file."
    )
    var payload: String

    func run() async throws {
        // 1. Resolve --payload: either inline JSON or @file reference (per research.md §R-2).
        let payloadData = try PayloadResolver.resolve(payload)

        // 2. Local validation (UUIDs, enums, payload size, typed payload decode).
        //    Fails fast with `schema.*` envelope before XPC round-trip.
        try SchemaValidator.validateCardPut(
            containerId: containerId,
            id: id,
            type: type,
            size: size,
            style: style,
            payload: payloadData
        )

        // 3. After validation, enums are guaranteed parseable.
        guard
            let cardType = CardType(rawValue: type),
            let cardSize = CardSize(rawValue: size),
            let cardStyle = CardStyle(rawValue: style)
        else {
            // Defensive — the validator above already guarantees these parse.
            throw XPCError(
                code: "schema.unknown_card_type",
                message: "Failed to resolve card enums after validation"
            )
        }

        let params = CardPutParams(
            containerId: containerId,
            id: id,
            type: cardType,
            size: cardSize,
            style: cardStyle,
            payload: payloadData
        )
        let paramsData = try JSONEncoder().encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "card.put",
            params: paramsData
        )

        let client = XPCClient()
        let response = try await client.execute(request)

        if response.ok {
            guard let data = response.data else {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Server returned ok=true but no data payload"
                )
            }
            let result: CardPutResult
            do {
                result = try JSONDecoder.iso8601Decoder.decode(CardPutResult.self, from: data)
            } catch {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode CardPutResult: \(error.localizedDescription)"
                )
            }
            let formatter = globals.outputMode.formatter()
            if !globals.isQuiet {
                try formatter.emit(success: result, requestId: response.requestId)
            }
        } else if let error = response.error {
            // Remote error — emit envelope with response.requestId and exit 3.
            // Per cli-surface §"Exit codes": server-returned errors ALWAYS exit 3.
            do {
                try Self.emitRemoteError(error, requestId: response.requestId, globals: globals)
            } catch let exitCode as ExitCode {
                Darwin.exit(exitCode.rawValue)
            }
        } else {
            throw XPCError(
                code: "xpc.decode_failure",
                message: "Server returned ok=false but no error payload"
            )
        }
    }

    // MARK: - Remote-error handler (extracted for testability, MY-1455)

    /// Production remote-error handler for card.put: emits the error envelope
    /// with response.requestId on stderr and throws ExitCode(3) (MY-1455).
    static func emitRemoteError(
        _ error: XPCError,
        requestId: String,
        globals: GlobalOptions
    ) throws {
        let remoteError = XPCError(
            code: error.code,
            message: error.message,
            field: error.field,
            got: error.got,
            allowed: error.allowed,
            cause: error.cause
        )
        let formatter = globals.outputMode.formatter()
        try formatter.emit(error: remoteError, requestId: requestId)
        throw ExitCode(3)
    }

    // MARK: - Payload resolution
    //
    // Payload @file resolution logic lives in `PayloadResolver` so the
    // unit-test target (which does not depend on `ArgumentParser`) can
    // exercise it directly.
}
