import ArgumentParser
import AIDashCore
import Foundation

/// `aidash container put` — create or update a container under a briefing.
///
/// Upsert by `(briefing_date, id)`. Cards under this container are NOT touched
/// (use `card put` separately). Per `contracts/cli-surface.md` §"container put".
///
/// Error-flow contract (per `AIDash.main` central handler):
///   - Local validation / XPC transport / decode failures → throw `XPCError`.
///     The central handler emits a single envelope via `JSONOutput()` and
///     exits via `ExitCodeMapper` (`schema.*` → 1, `xpc.*` → 2, else 3).
///   - Remote `ok=false` errors → emit the envelope here with the
///     `response.requestId` and throw `ExitCode`. `run()` catches the
///     `ExitCode` and calls `Darwin.exit` so the central handler does NOT
///     re-emit `schema.argument_validation_failed`.
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

        // Step 2: Local validation — fail fast, never round-trip invalid input.
        try SchemaValidator.validateContainerPut(
            id: id,
            title: title,
            order: order,
            layout: layout,
            style: style
        )

        // Step 3: Build params.
        // Layout/style enums are already validated by SchemaValidator, so the
        // initializers below cannot fail in practice — but route through
        // XPCError if they somehow do, so the central handler can emit cleanly
        // rather than crashing.
        guard let containerLayout = ContainerLayout(rawValue: layout) else {
            throw XPCError(
                code: "schema.unknown_container_layout",
                message: "Unknown layout '\(layout)'",
                field: "layout",
                got: layout,
                allowed: ContainerLayout.allCases.map(\.rawValue)
            )
        }
        guard let cardStyle = CardStyle(rawValue: style) else {
            throw XPCError(
                code: "schema.unknown_card_style",
                message: "Unknown style '\(style)'",
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
    // Per `cli-surface.md` §"Exit codes" and the central-handler contract:
    //   - `ok=true`  → emit success envelope on stdout (unless `--quiet`),
    //     return normally. Decode failures throw `XPCError` so the central
    //     handler emits a single error envelope.
    //   - `ok=false` → emit error envelope on stderr verbatim with
    //     `response.requestId`, then throw `ExitCode(ExitCodeMapper.code(for:))`
    //     so `run()` can `Darwin.exit` without a second emit at the central
    //     handler. Exit-code class is taken from `ExitCodeMapper`:
    //       * `schema.*` → 1
    //       * `xpc.*`    → 2
    //       * anything else (briefing.* / container.* / cloudkit.* / internal.*) → 3
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
                let formatter = globals.outputMode.formatter(requestId: response.requestId)
                try formatter.emit(success: result)
            }
            return
        }

        if let remoteError = response.error {
            let formatter = globals.outputMode.formatter(requestId: response.requestId)
            try formatter.emit(error: remoteError)
            throw ExitCode(ExitCodeMapper.code(for: remoteError))
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
}
