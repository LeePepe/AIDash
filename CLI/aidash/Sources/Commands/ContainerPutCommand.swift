import ArgumentParser
import AIDashCore
import Foundation

/// `aidash container put` — create or update a container under a briefing.
///
/// Upsert by `(briefing_date, id)`. Cards under this container are NOT touched
/// (use `card put` separately). Per `contracts/cli-surface.md` §"container put".
///
/// Error-flow contract (per `AIDash.main` central handler + cli-surface.md
/// §"Exit codes"):
///   - Local validation failures → throw `XPCError` with `schema.*` code.
///     The central handler emits a single envelope via `JSONOutput()` and
///     exits 1 via `ExitCodeMapper`.
///   - XPC transport failures (`xpc.*`) → propagate `XPCError` from
///     `XPCClient.execute`. Central handler emits + exits 2.
///   - Remote `ok=false` (server/app-side errors — any code class) → emit
///     the envelope here (so it carries `response.requestId`) and throw
///     `ExitCode(3)`. `run()` catches that `ExitCode` and `Darwin.exit`s
///     so the central handler does NOT re-emit `schema.argument_validation_failed`.
///     Per `cli-surface.md` §"Exit codes": code 3 is "app-side error" —
///     remote `schema.*` and remote `xpc.*` are still server-side returns
///     and stay on exit 3. Only LOCAL `schema.*` / `xpc.*` get the 1 / 2
///     mapping from `ExitCodeMapper`.
struct ContainerPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a container."
    )

    @OptionGroup var globals: GlobalOptions

    // MARK: - Required Flags

    @Option(name: .long, help: "The briefing date (YYYY-MM-DD, 'today', or 'yesterday').")
    var briefingDate: String

    @Option(name: .long, help: "Caller-supplied container UUID.")
    var id: String

    @Option(name: .long, help: "Container heading.")
    var title: String

    @Option(name: .long, help: "Sparse sort order (10, 20, 30...).")
    var order: Int

    // MARK: - Optional Flags

    @Option(name: .long, help: "Optional secondary heading.")
    var subtitle: String?

    @Option(name: .long, help: "Container rendering hint (auto, list, grid, hero).")
    var layout: String = "auto"

    @Option(name: .long, help: "Visual style (neutral, success, warning, accent).")
    var style: String = "neutral"

    // MARK: - Run

    func run() async throws {
        // Step 1: Resolve and validate date locally.
        // Local schema failure → throw XPCError → central handler emits and
        // exits 1 with a single `schema.*` envelope.
        let resolvedDate = DateResolver.resolve(briefingDate)
        try validateDate(resolvedDate)

        // Step 2: Local validation.
        //
        // We validate layout/style locally with the CLI-contract codes
        // (`schema.invalid_layout` / `schema.invalid_style` per
        // `cli-surface.md` §"aidash container put" Errors) BEFORE delegating
        // to `SchemaValidator.validateContainerPut`. The shared validator's
        // enum-check error codes are the AIDashCore internal taxonomy
        // (`schema.unknown_container_layout` / `schema.unknown_card_style`)
        // and aren't the documented `aidash container put` surface — the
        // CLI must rename them to match the published command contract.
        try validateLayout(layout)
        try validateStyle(style)
        try SchemaValidator.validateContainerPut(
            id: id,
            briefingDate: resolvedDate,
            title: title,
            order: order,
            layout: layout,
            style: style
        )

        // Step 3: Build params.
        // Layout/style enums were already validated above, so these
        // initializers cannot fail in practice — but route through the
        // CLI-contract `schema.invalid_*` codes if they somehow do.
        guard let containerLayout = ContainerLayout(rawValue: layout) else {
            throw XPCError(
                code: "schema.invalid_layout",
                message: "Invalid layout '\(layout)'",
                field: "layout",
                got: layout,
                allowed: ContainerLayout.allCases.map(\.rawValue)
            )
        }
        guard let cardStyle = CardStyle(rawValue: style) else {
            throw XPCError(
                code: "schema.invalid_style",
                message: "Invalid style '\(style)'",
                field: "style",
                got: style,
                allowed: CardStyle.allCases.map(\.rawValue)
            )
        }

        let params = ContainerPutParams(
            briefingDate: resolvedDate,
            id: id,
            title: title,
            subtitle: subtitle,
            order: order,
            layout: containerLayout,
            style: cardStyle
        )

        // Step 4: Encode params and build XPC request.
        let requestId = UUID().uuidString
        let paramsData = try JSONEncoder().encode(params)

        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "container.put",
            params: paramsData
        )

        // Step 5: Send via XPC. Transport failures surface as XPCError with
        // `xpc.*` code, which the central handler renders as exit 2.
        let response = try await XPCClient().execute(request)

        // Step 6: Handle response.
        //
        // `Self.emit` either returns (success), throws `XPCError` (decode
        // failure / malformed response — central handler emits + exits), or
        // throws `ExitCode` (remote error — `Self.emit` already wrote the
        // envelope on stderr with the correct `response.requestId`, so we
        // must NOT let the throw fall through to the central handler or it
        // will emit a second `schema.argument_validation_failed` envelope).
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
    //   - `ok=true`  → emit success envelope on stdout (unless `--quiet`),
    //     return normally. Decode failures throw `XPCError xpc.decode_failure`
    //     (transport-class) so the central handler emits a single envelope
    //     and exits 2.
    //   - `ok=false` → server returned an app-side error. Emit the error
    //     envelope on stderr verbatim with `response.requestId`, then throw
    //     `ExitCode(3)`. Per the contract: code 3 is "App-side error"; every
    //     remote `ok=false` belongs there regardless of code class (remote
    //     `schema.*` and remote `xpc.*` are still server returns). The
    //     `ExitCodeMapper` 1/2 mapping is only for LOCAL validation /
    //     transport failures that throw `XPCError` to the central handler.
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
            let result: ContainerPutResult
            do {
                result = try JSONDecoder.iso8601Decoder.decode(
                    ContainerPutResult.self, from: data
                )
            } catch {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode ContainerPutResult: \(error.localizedDescription)"
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

    // MARK: - Helpers

    /// Validate resolved date is a valid YYYY-MM-DD string.
    /// Local — never round-trip an obviously-invalid date through XPC.
    private func validateDate(_ dateString: String) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        guard formatter.date(from: dateString) != nil else {
            throw XPCError(
                code: "schema.invalid_date",
                message: "Date '\(dateString)' is not in YYYY-MM-DD format",
                field: "briefingDate",
                got: dateString
            )
        }
    }

    /// Validate `--layout` against `ContainerLayout` with the CLI-contract
    /// error code (`cli-surface.md` §"aidash container put" Errors).
    private func validateLayout(_ value: String) throws {
        guard ContainerLayout(rawValue: value) != nil else {
            throw XPCError(
                code: "schema.invalid_layout",
                message: "Invalid layout '\(value)'",
                field: "layout",
                got: value,
                allowed: ContainerLayout.allCases.map(\.rawValue)
            )
        }
    }

    /// Validate `--style` against `CardStyle` with the CLI-contract error
    /// code (`cli-surface.md` §"aidash container put" Errors).
    private func validateStyle(_ value: String) throws {
        guard CardStyle(rawValue: value) != nil else {
            throw XPCError(
                code: "schema.invalid_style",
                message: "Invalid style '\(value)'",
                field: "style",
                got: value,
                allowed: CardStyle.allCases.map(\.rawValue)
            )
        }
    }
}
