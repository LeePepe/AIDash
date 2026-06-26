import ArgumentParser
import AIDashCore
import Foundation

/// `aidash briefing get --date <YYYY-MM-DD|today|yesterday|latest>`
///
/// Reads a Briefing (containers + cards with payload Data) for the given date.
/// See `specs/001-core-briefing-cli/contracts/cli-surface.md` §"briefing get".
///
/// Flow (matches sibling commands like `BriefingPublishCommand`):
///   1. Resolve `--date` sugar (`today`/`yesterday`) to YYYY-MM-DD; pass
///      `latest` through unchanged (resolved on the app side per contract).
///   2. Local validation via `SchemaValidator.validateBriefingGet`. Failures
///      throw `XPCError` with `schema.*` codes; the central handler in
///      `AIDash.main` maps that to exit code 1.
///   3. Build `BriefingGetParams` (with `--include-drafts`) and dispatch via
///      `XPCClient.execute`.
///   4. On success: decode `BriefingGetResult` and emit via the active
///      formatter (`--json` ⇒ envelope on stdout; default ⇒ pretty payload).
///   5. On remote error: emit envelope on stderr and exit 3 (per cli-surface
///      §"Exit codes" — server-returned codes are ALWAYS exit 3, even if the
///      `code` happens to start with `schema.` or `xpc.`; those prefixes are
///      reserved for LOCAL classification only).
///
/// Exit codes (per `contracts/cli-surface.md`):
///   - 0 — success
///   - 1 — local validation failure (`schema.*`, thrown via central handler)
///   - 2 — XPC transport failure (`xpc.*`, thrown via central handler)
///   - 3 — remote error (anything returned in `XPCResponse.error`)
struct BriefingGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read a briefing (containers + cards)."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Briefing date (YYYY-MM-DD, 'today', 'yesterday', or 'latest').")
    var date: String

    @Flag(name: .customLong("include-drafts"),
          help: "Include draft (unpublished) briefings in results.")
    var includeDrafts: Bool = false

    /// Executes the `briefing get` subcommand end-to-end.
    ///
    /// - Throws:
    ///   - `XPCError` with `schema.*` code on local validation failure
    ///     (central handler maps to exit 1).
    ///   - `XPCError` with `xpc.*` code on local XPC transport failure
    ///     (central handler maps to exit 2).
    ///   - `XPCError` re-thrown from the remote `XPCResponse.error`
    ///     envelope. To keep server-returned errors mapped to exit 3
    ///     regardless of code prefix, this method writes the error envelope
    ///     and calls `Darwin.exit(3)` directly rather than relying on the
    ///     central prefix mapper (per the contract's reserved-prefix rule).
    func run() async throws {
        let resolvedDate = Self.resolveDate(date)
        try SchemaValidator.validateBriefingGet(date: resolvedDate)

        let params = BriefingGetParams(date: resolvedDate, includeDrafts: includeDrafts)
        let paramsData = try JSONEncoder().encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "briefing.get",
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
            let result: BriefingGetResult
            do {
                result = try JSONDecoder.iso8601Decoder.decode(
                    BriefingGetResult.self, from: data
                )
            } catch {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode BriefingGetResult: \(error.localizedDescription)"
                )
            }
            let formatter = globals.outputMode.formatter()
            if !globals.isQuiet {
                try formatter.emit(success: result.briefing, requestId: response.requestId)
            }
        } else if let error = response.error {
            // Per `cli-surface.md` §"Exit codes": any error returned inside
            // `XPCResponse.error` is a REMOTE failure and ALWAYS exits 3,
            // even if its `code` starts with `schema.` or `xpc.`. Those
            // prefixes are reserved for LOCAL classification only, so we
            // emit the envelope and exit 3 directly here rather than letting
            // the central prefix-based mapper remap it to 1 or 2.
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

    /// Resolves CLI date sugar per `contracts/cli-surface.md` §"briefing get".
    ///
    ///   - `"today"`      → today (local time per device, YYYY-MM-DD)
    ///   - `"yesterday"`  → previous day (local time per device, YYYY-MM-DD)
    ///   - `"latest"`     → pass-through (resolved on the app side)
    ///   - any other      → unchanged (handed to `SchemaValidator`)
    ///
    /// The lowercase comparison means `Today`/`TODAY`/`Latest` all work.
    static func resolveDate(_ input: String) -> String {
        switch input.lowercased() {
        case "today", "yesterday":
            return DateResolver.resolve(input)
        case "latest":
            return "latest"
        default:
            return input
        }
    }
}
