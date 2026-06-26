import ArgumentParser
import AIDashCore
import Foundation

/// `aidash briefing put --date <YYYY-MM-DD|today|yesterday> --generated-by <agent>`
///
/// Creates or updates a briefing's top-level metadata. With `--published`,
/// also publishes atomically. Per `contracts/cli-surface.md` §"briefing put".
///
/// Error-flow contract (matches sibling commands like `BriefingGetCommand` /
/// `ContainerPutCommand`):
///   - Local validation failures → throw `XPCError` with `schema.*` code.
///     The central handler in `AIDash.main` emits a single envelope via
///     `JSONOutput` and exits 1 via `ExitCodeMapper`.
///   - XPC transport failures (`xpc.*`) → propagate `XPCError` from
///     `XPCClient.execute`. Central handler emits + exits 2.
///   - Remote `ok=false` → emit the envelope here (so it carries
///     `response.requestId`) and throw `ExitCode(3)`. Per
///     `cli-surface.md` §"Exit codes" a server-returned error is ALWAYS
///     exit 3, even if its `code` happens to start with `schema.` or
///     `xpc.` (those prefixes are reserved for LOCAL classification).
struct BriefingPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a briefing's top-level metadata."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Briefing date (YYYY-MM-DD, 'today', or 'yesterday').")
    var date: String

    @Option(name: .long, help: "Name of the agent/script publishing this briefing.")
    var generatedBy: String

    @Flag(name: .long, help: "Also publish the briefing atomically.")
    var published: Bool = false

    func run() async throws {
        // Step 1: resolve and validate date locally.
        let resolvedDate = DateResolver.resolve(date)
        try SchemaValidator.validateBriefingPut(
            date: resolvedDate,
            generatedBy: generatedBy
        )

        // Step 2: build params + XPC request.
        let params = BriefingPutParams(
            date: resolvedDate,
            generatedBy: generatedBy,
            published: published
        )
        let paramsData = try JSONEncoder().encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "briefing.put",
            params: paramsData
        )

        // Step 3: send via XPC. Transport failures surface as `XPCError xpc.*`
        // and the central handler renders exit 2.
        let response = try await XPCClient().execute(request)

        // Step 4: render response. `Self.emit` either returns (success),
        // throws `XPCError xpc.decode_failure` (malformed reply — central
        // handler emits and exits 2), or throws `ExitCode(3)` after writing
        // the remote envelope. Convert the latter into `Darwin.exit` so the
        // central handler does NOT re-emit a generic
        // `schema.argument_validation_failed` envelope on top of the
        // already-written remote envelope.
        do {
            try Self.emit(response: response, globals: globals)
        } catch let exitCode as ExitCode {
            Darwin.exit(exitCode.rawValue)
        }
    }

    // MARK: - Emit (extracted so tests can drive both branches with a
    // synthetic `XPCResponse`).

    static func emit(
        response: XPCResponse,
        globals: GlobalOptions
    ) throws {
        if response.ok {
            guard let data = response.data else {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Server returned ok=true but no data payload"
                )
            }
            let result: BriefingPutResult
            do {
                result = try JSONDecoder.iso8601Decoder.decode(
                    BriefingPutResult.self, from: data
                )
            } catch {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode BriefingPutResult: \(error.localizedDescription)"
                )
            }
            if !globals.isQuiet {
                let formatter = globals.outputMode.formatter()
                try formatter.emit(success: result, requestId: response.requestId)
            }
            return
        }

        if let remoteError = response.error {
            let formatter = globals.outputMode.formatter()
            try formatter.emit(error: remoteError, requestId: response.requestId)
            // Per cli-surface.md §"Exit codes": code 3 = App-side error.
            // ANY server-returned ok=false maps to 3 regardless of code class.
            throw ExitCode(3)
        }

        throw XPCError(
            code: "xpc.decode_failure",
            message: "Server returned ok=false but no error payload"
        )
    }
}
