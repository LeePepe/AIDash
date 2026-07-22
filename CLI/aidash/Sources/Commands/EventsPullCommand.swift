import ArgumentParser
import AIDashCore
import Foundation

/// `aidash events pull --since <...> [--until <...>] [--card-id <uuid>]
///   [--action done|star] [--item-ref <ref>]`
///
/// Reads append-only user events back for agent consumption — the read half
/// of the spec 002 star feedback loop (the app is the only writer; the CLI
/// NEVER writes events, constitution §II). Stateless: agents track their own
/// high-water mark. See `contracts/cli-surface.md` §"events pull" and
/// `specs/002-star-radar-feedback/tasks.md` T002.
///
/// Flow (matches sibling commands like `BriefingGetCommand`):
///   1. Parse/validate flags locally (`--since` is required; date-only values
///      mean LOCAL midnight per the contract). Failures throw `XPCError`
///      with `schema.*` codes → central handler exits 1.
///   2. Build `EventsPullParams` and dispatch `events.pull` via `XPCClient`.
///   3. On success decode `EventsPullResult` and emit:
///      - default (human mode): newline-delimited JSON (one event per line)
///        on stdout — machine-readable even without `--json` (contract:
///        "always JSON"). This is the essential payload, so it is emitted
///        even under `--quiet` (errors still go to stderr).
///      - `--json`: the standard success envelope wrapping the full result.
///   4. On remote error: emit the error envelope and exit 3 directly (per
///      cli-surface §"Exit codes" — server-returned codes are ALWAYS exit 3;
///      `schema.`/`xpc.` prefixes are reserved for LOCAL classification).
struct EventsPullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pull user events since a given timestamp."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Lower bound, inclusive: ISO-8601 timestamp, YYYY-MM-DD (local midnight), or 'today'/'yesterday'.")
    var since: String

    @Option(name: .long, help: "Upper bound, exclusive. Same formats as --since. Defaults to now.")
    var until: String?

    @Option(name: .customLong("card-id"), help: "Filter by a single card UUID.")
    var cardId: String?

    @Option(name: .long, help: "Filter by action: done|star.")
    var action: String?

    @Option(name: .customLong("item-ref"), help: "Filter by itemRef (e.g. a radar repo URL).")
    var itemRef: String?

    /// Executes the `events pull` subcommand end-to-end.
    ///
    /// - Throws:
    ///   - `XPCError` with `schema.*` code on local validation failure
    ///     (central handler maps to exit 1).
    ///   - `XPCError` with `xpc.*` code on local XPC transport failure
    ///     (central handler maps to exit 2).
    ///   - `XPCError` re-thrown from the remote `XPCResponse.error` envelope;
    ///     remote failures write the envelope and `Darwin.exit(3)` directly
    ///     (see the reserved-prefix rule in `BriefingGetCommand`).
    func run() async throws {
        let sinceDate = try Self.parseBound(since, field: "--since")
        let untilDate = try until.map { try Self.parseBound($0, field: "--until") }
        let parsedAction = try action.map { try Self.parseAction($0) }
        if let cardId {
            try Self.validateCardId(cardId)
        }

        let params = EventsPullParams(
            since: sinceDate,
            until: untilDate,
            cardId: cardId,
            action: parsedAction,
            itemRef: itemRef
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let paramsData = try encoder.encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "events.pull",
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
            let result: EventsPullResult
            do {
                result = try JSONDecoder.iso8601Decoder.decode(
                    EventsPullResult.self, from: data
                )
            } catch {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode EventsPullResult: \(error.localizedDescription)"
                )
            }
            switch globals.outputMode {
            case .json:
                try JSONOutput().emit(success: result, requestId: response.requestId)
            case .human:
                // Contract: default output is newline-delimited JSON. The
                // events ARE the payload (not decoration), so --quiet does
                // not suppress them.
                let jsonl = try Self.renderJSONL(result.events)
                if !jsonl.isEmpty {
                    FileHandle.standardOutput.write(Data((jsonl + "\n").utf8))
                }
            }
        } else if let error = response.error {
            // Remote failure: ALWAYS exit 3, regardless of code prefix (see
            // the reserved-prefix rule documented in BriefingGetCommand).
            let remoteError = XPCError(
                code: error.code,
                message: error.message,
                field: error.field,
                got: error.got,
                allowed: error.allowed,
                cause: error.cause
            )
            let formatter = globals.outputMode.formatter()
            try formatter.emit(error: remoteError, requestId: response.requestId)
            Darwin.exit(3)
        } else {
            throw XPCError(
                code: "xpc.decode_failure",
                message: "Server returned ok=false but no error payload"
            )
        }
    }

    // MARK: - Internal helpers (visible to tests)

    /// Parses a `--since`/`--until` bound per cli-surface §"events pull":
    ///
    ///   - `"today"` / `"yesterday"` → that day at LOCAL midnight (via
    ///     `DateResolver`, case-insensitive)
    ///   - `YYYY-MM-DD`              → LOCAL midnight of that day
    ///   - full ISO-8601 timestamp   → the absolute instant
    ///
    /// Anything else throws `schema.invalid_argument` (→ exit 1).
    static func parseBound(_ input: String, field: String) throws -> Date {
        let resolved = DateResolver.resolve(input)

        // Date-only → local midnight. Strict + length-pinned so ISO-8601
        // timestamps never fall into this branch.
        if resolved.count == 10 {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.timeZone = .current
            dayFormatter.isLenient = false
            if let day = dayFormatter.date(from: resolved) {
                return day
            }
        }

        // Full ISO-8601 timestamp (with or without fractional seconds).
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let timestamp = isoFractional.date(from: resolved) {
            return timestamp
        }
        if let timestamp = ISO8601DateFormatter().date(from: resolved) {
            return timestamp
        }

        throw XPCError(
            code: "schema.invalid_argument",
            message: "Invalid \(field) value: expected an ISO-8601 timestamp, YYYY-MM-DD, or 'today'/'yesterday'.",
            field: field,
            got: input,
            allowed: ["ISO-8601", "YYYY-MM-DD", "today", "yesterday"]
        )
    }

    /// Parses `--action` into a `UserEventAction`, rejecting unknown values
    /// with the allowed set listed for the agent (→ exit 1).
    static func parseAction(_ input: String) throws -> UserEventAction {
        guard let action = UserEventAction(rawValue: input.lowercased()) else {
            throw XPCError(
                code: "schema.invalid_argument",
                message: "Unknown --action value.",
                field: "--action",
                got: input,
                allowed: UserEventAction.allCases.map(\.rawValue)
            )
        }
        return action
    }

    /// Validates `--card-id` as a UUID (contract: CLI validates UUID format
    /// locally → exit 1 on failure).
    static func validateCardId(_ input: String) throws {
        guard UUID(uuidString: input) != nil else {
            throw XPCError(
                code: "schema.invalid_argument",
                message: "Invalid --card-id value: expected a UUID.",
                field: "--card-id",
                got: input,
                allowed: nil
            )
        }
    }

    /// Renders events as newline-delimited JSON (the contract's default
    /// output). Keys are sorted for deterministic diffing; timestamps are
    /// ISO-8601; `itemRef` is omitted when nil (synthesized Codable drops
    /// absent optionals).
    static func renderJSONL(_ events: [UserEvent]) throws -> String {
        try events
            .map { try Self.jsonlEncoder.encode($0) }
            .map { String(bytes: $0, encoding: .utf8) ?? "" }
            .joined(separator: "\n")
    }

    private static let jsonlEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
