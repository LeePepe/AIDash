import ArgumentParser
import AIDashCore
import Foundation

/// `aidash container delete` — delete a container and all of its child cards.
///
/// See `specs/001-core-briefing-cli/contracts/cli-surface.md` §"container delete".
///
/// Flags (per contract):
///   --id <uuid>   required — the container's UUID
///
/// Plus global `--json`/`--quiet` (declared on `GlobalOptions`).
///
/// Behavior:
///   1. Local validation via `SchemaValidator.validateContainerDelete`. Fail fast
///      (exit 1) with a `schema.*` envelope on stderr.
///   2. Build `ContainerDeleteParams` and dispatch via `XPCClient`.
///   3. On success: decode `ContainerDeleteResult`, emit via the active formatter.
///   4. On remote error (e.g. `container.not_found`): re-throw as `XPCError` so
///      `AIDash.main`'s central handler emits the envelope and maps the exit code.
///
/// Deleting a container cascades to its child cards (the app-side handler removes
/// the `ContainerModel`, and SwiftData deletes the owned `CardModel`s). Delete is
/// idempotent from the caller's perspective only in that a missing container
/// returns a `container.not_found` remote error (exit 3), never a silent success.
///
/// Exit codes (mapped centrally by `AIDash.main` via `ExitCodeMapper`):
///   0 — success
///   1 — local validation (`schema.*`)
///   2 — XPC transport (`xpc.*`)
///   3 — remote error (everything else, incl. `container.not_found`)
struct ContainerDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a container and its child cards."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "The container's UUID.")
    var id: String

    func run() async throws {
        // 1. Local validation (non-empty + valid UUID). Fails fast with a
        //    `schema.*` envelope before any XPC round-trip.
        try SchemaValidator.validateContainerDelete(id: id)

        // 2. Build params + request.
        let params = ContainerDeleteParams(id: id)
        let paramsData = try JSONEncoder().encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "container.delete",
            params: paramsData
        )

        // 3. Dispatch. Transport failures surface as `XPCError` (`xpc.*`) which
        //    the central handler renders as exit 2.
        let response = try await XPCClient().execute(request)

        // 4. Handle response.
        try Self.emit(response: response, globals: globals)
    }

    // MARK: - Emit (extracted so tests can drive both branches with a
    // synthetic `XPCResponse`).
    //
    // Per `cli-surface.md` §"Exit codes":
    //   - `ok=true`  → emit success envelope on stdout (unless `--quiet`).
    //     A missing data payload is tolerated: `ContainerDeleteResult` is empty,
    //     so an `ok=true` with no `data` still decodes to an empty result.
    //   - `ok=false` → remote error. Re-throw as `XPCError` so the central
    //     handler emits the envelope and maps to exit 3 (App-side error).
    static func emit(
        response: XPCResponse,
        globals: GlobalOptions
    ) throws {
        if response.ok {
            // `ContainerDeleteResult` carries no fields; decode when present,
            // otherwise synthesize the empty result so a bodyless ok=true still
            // reports success.
            let result: ContainerDeleteResult
            if let data = response.data, !data.isEmpty {
                do {
                    result = try JSONDecoder.iso8601Decoder.decode(
                        ContainerDeleteResult.self, from: data
                    )
                } catch {
                    throw XPCError(
                        code: "xpc.decode_failure",
                        message: "Failed to decode ContainerDeleteResult: \(error.localizedDescription)"
                    )
                }
            } else {
                result = ContainerDeleteResult()
            }
            if !globals.isQuiet {
                let formatter = globals.outputMode.formatter()
                try formatter.emit(success: result, requestId: response.requestId)
            }
            return
        }

        if let remoteError = response.error {
            throw XPCError(
                code: remoteError.code,
                message: remoteError.message,
                field: remoteError.field,
                got: remoteError.got,
                allowed: remoteError.allowed,
                cause: remoteError.cause
            )
        }

        throw XPCError(
            code: "xpc.decode_failure",
            message: "Server returned ok=false but no error payload"
        )
    }
}
