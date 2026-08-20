import ArgumentParser
import AIDashCore
import Foundation

/// `aidash card delete` — delete a single card by its UUID.
///
/// See `specs/001-core-briefing-cli/contracts/cli-surface.md` §"card delete".
///
/// Flags (per contract):
///   --id <uuid>   required — the card's UUID
///
/// Plus global `--json`/`--quiet` (declared on `GlobalOptions`).
///
/// Behavior:
///   1. Local validation via `SchemaValidator.validateCardDelete`. Fail fast
///      (exit 1) with a `schema.*` envelope on stderr.
///   2. Build `CardDeleteParams` and dispatch via `XPCClient`.
///   3. On success: decode `CardDeleteResult`, emit via the active formatter.
///   4. On remote error (e.g. `card.not_found`): emit the error envelope
///      with `response.requestId` on stderr and exit 3 directly (MY-1455).
///
/// Unlike `container delete`, this removes only the named card; its parent
/// container and sibling cards are untouched.
///
/// Exit codes (mapped centrally by `AIDash.main` via `ExitCodeMapper`):
///   0 — success
///   1 — local validation (`schema.*`)
///   2 — XPC transport (`xpc.*`)
///   3 — remote error (everything else, incl. `card.not_found`)
struct CardDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a card."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "The card's UUID.")
    var id: String

    func run() async throws {
        // 1. Local validation (non-empty + valid UUID). Fails fast with a
        //    `schema.*` envelope before any XPC round-trip.
        try SchemaValidator.validateCardDelete(id: id)

        // 2. Build params + request.
        let params = CardDeleteParams(id: id)
        let paramsData = try JSONEncoder().encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "card.delete",
            params: paramsData
        )

        // 3. Dispatch. Transport failures surface as `XPCError` (`xpc.*`) which
        //    the central handler renders as exit 2.
        let response = try await XPCClient().execute(request)

        // 4. Handle response.
        do {
            try Self.emit(response: response, globals: globals)
        } catch let exitCode as ExitCode {
            Darwin.exit(exitCode.rawValue)
        }
    }

    // MARK: - Emit (extracted so tests can drive both branches with a
    // synthetic `XPCResponse`).
    //
    // Per `cli-surface.md` §"Exit codes":
    //   - `ok=true`  → emit success envelope (unless `--quiet`). Empty result
    //     type, so a bodyless ok=true still reports success.
    //   - `ok=false` with error → emit the remote error envelope on stderr
    //     with `response.requestId` and throw `ExitCode(3)` (MY-1455).
    //   - `ok=false` without error → malformed protocol reply; throw
    //     `xpc.decode_failure` (exit 2 via central handler).
    static func emit(
        response: XPCResponse,
        globals: GlobalOptions
    ) throws {
        if response.ok {
            let result: CardDeleteResult
            if let data = response.data, !data.isEmpty {
                do {
                    result = try JSONDecoder.iso8601Decoder.decode(
                        CardDeleteResult.self, from: data
                    )
                } catch {
                    throw XPCError(
                        code: "xpc.decode_failure",
                        message: "Failed to decode CardDeleteResult: \(error.localizedDescription)"
                    )
                }
            } else {
                result = CardDeleteResult()
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
            throw ExitCode(3)
        }

        throw XPCError(
            code: "xpc.decode_failure",
            message: "Server returned ok=false but no error payload"
        )
    }
}
