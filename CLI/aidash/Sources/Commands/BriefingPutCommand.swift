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

        // Step 3: send via XPC.
        //
        // `XPCClient.execute` throws on BOTH local transport failures AND
        // remote `ok=false` returns (the actor's `resultForResponse` maps
        // remote envelopes to `.failure(remoteError)` and rethrows). We
        // disambiguate here by the error's code prefix:
        //
        //   - `xpc.*` codes raised pre-reply are LOCAL transport failures
        //     (`xpc.transport_failure`, `xpc.timeout`, `xpc.proxy_unavailable`,
        //     `xpc.invalidated`, `xpc.interrupted`, `xpc.decode_failure`).
        //     Rethrow so the central handler in `AIDash.main` exits 2 via
        //     `ExitCodeMapper`. Per `cli-surface.md` §"Exit codes" the
        //     `xpc.*` / `schema.*` prefix rule on LOCAL classification is
        //     what determines 1 / 2.
        //
        //   - Any other code is a REMOTE error returned by the app. Per the
        //     same contract, server-returned errors ALWAYS exit 3 regardless
        //     of code class (including remote `schema.*`). Emit the server
        //     envelope on stderr with the request id and exit 3 directly,
        //     so the central handler doesn't double-emit and so the
        //     prefix-based mapper can't downgrade a remote `schema.*` to
        //     exit 1.
        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            // `handleExecuteError` never returns normally:
            //   - Local `xpc.*` → rethrows the original `XPCError`, which
            //     escapes this `do/catch` and reaches the central handler
            //     in `AIDash.main` → exit 2 via `ExitCodeMapper`.
            //   - Remote (any non-`xpc.*` code) → writes the server
            //     envelope to stderr with `requestId`, then throws
            //     `ExitCode(3)`, which we map to `Darwin.exit(3)` so the
            //     central handler doesn't double-emit.
            do {
                try Self.handleExecuteError(error, requestId: requestId, globals: globals)
            } catch let exitCode as ExitCode {
                Darwin.exit(exitCode.rawValue)
            }
            // Unreachable: `handleExecuteError` always throws.
            return
        }

        // Step 4: render response. `Self.emit` either returns (success),
        // throws `XPCError xpc.decode_failure` (malformed reply — central
        // handler emits and exits 2), or throws `ExitCode(3)` after writing
        // the remote envelope (defence-in-depth for any direct caller that
        // bypasses `execute` and hands a synthetic `ok=false` response in).
        do {
            try Self.emit(response: response, globals: globals)
        } catch let exitCode as ExitCode {
            Darwin.exit(exitCode.rawValue)
        }
    }

    // MARK: - Execute-error triage (extracted so tests can drive both
    // branches without standing up a real `XPCClient`).
    //
    // `XPCClient.execute` throws a single `XPCError` type for two distinct
    // failure classes (the actor's `resultForResponse` re-throws remote
    // envelope errors instead of returning the failed `XPCResponse`).
    // Per `cli-surface.md` §"Exit codes" we MUST disambiguate before
    // exiting:
    //
    //   - Local `xpc.*` (transport/timeout/decode/etc.) → rethrow so the
    //     central handler maps via `ExitCodeMapper` → exit 2.
    //   - Anything else → REMOTE server error. Per the contract every
    //     server-returned error exits 3 regardless of code class, so
    //     remote `schema.*` and remote `xpc.*` still exit 3 (the prefix
    //     rule only applies to LOCAL classification). Emit the envelope
    //     on stderr with the request id and throw `ExitCode(3)` so the
    //     caller can `Darwin.exit` without the central handler
    //     double-emitting on top.
    static func handleExecuteError(
        _ error: XPCError,
        requestId: String,
        globals: GlobalOptions
    ) throws {
        if error.code.hasPrefix("xpc.") {
            throw error
        }
        let formatter = globals.outputMode.formatter()
        try formatter.emit(error: error, requestId: requestId)
        throw ExitCode(3)
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
