import ArgumentParser
import AIDashCore
import Foundation

/// `aidash container put` — create or update a container under a briefing.
///
/// Upsert by `(briefing_date, id)`. Cards under this container are NOT touched
/// (use `card put` separately). Per `contracts/cli-surface.md` §"container put".
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
        let resolvedDate = DateResolver.resolve(briefingDate)
        do {
            try validateDate(resolvedDate)
        } catch let error as XPCError {
            try globals.outputMode.formatter(requestId: nil).emit(error: error)
            throw ExitCode(ExitCodeMapper.code(for: error))
        }

        // Step 2: Local validation — fail fast, never round-trip invalid input.
        do {
            try SchemaValidator.validateContainerPut(
                id: id,
                title: title,
                order: order,
                layout: layout,
                style: style
            )
        } catch let error as XPCError {
            try globals.outputMode.formatter(requestId: nil).emit(error: error)
            throw ExitCode(ExitCodeMapper.code(for: error))
        }

        // Step 3: Build params.
        // Layout/style enums are already validated by SchemaValidator, so the
        // initializers below cannot fail — but we route through XPCError if they
        // somehow do, rather than crashing.
        guard let containerLayout = ContainerLayout(rawValue: layout) else {
            let error = XPCError(
                code: "schema.unknown_container_layout",
                message: "Unknown layout '\(layout)'",
                field: "layout",
                got: layout,
                allowed: ContainerLayout.allCases.map(\.rawValue)
            )
            try globals.outputMode.formatter(requestId: nil).emit(error: error)
            throw ExitCode(ExitCodeMapper.code(for: error))
        }
        guard let cardStyle = CardStyle(rawValue: style) else {
            let error = XPCError(
                code: "schema.unknown_card_style",
                message: "Unknown style '\(style)'",
                field: "style",
                got: style,
                allowed: CardStyle.allCases.map(\.rawValue)
            )
            try globals.outputMode.formatter(requestId: nil).emit(error: error)
            throw ExitCode(ExitCodeMapper.code(for: error))
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
        // `xpc.*` code, which ExitCodeMapper renders as exit 2.
        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            try globals.outputMode.formatter(requestId: requestId).emit(error: error)
            throw ExitCode(ExitCodeMapper.code(for: error))
        }

        // Step 6: Handle response.
        try Self.emit(response: response, globals: globals, requestedId: requestId)
    }

    // MARK: - Emit (extracted so tests can drive the success path with a
    // synthetic `XPCResponse`).
    //
    // Per `cli-surface.md` §"Exit codes":
    //   - `ok=true`  → emit JSON / human envelope on stdout, return (exit 0).
    //   - `ok=false` → emit error envelope on stderr verbatim, exit code class
    //     is taken from `ExitCodeMapper`:
    //       * `schema.*` → 1
    //       * `xpc.*`    → 2
    //       * anything else (briefing.* / container.* / cloudkit.* / internal.*) → 3
    //     The reviewer's contract reading is that **any** server-returned
    //     `ok=false` is exit 3, but the published `cli-surface.md` exit-code
    //     table still maps by code class — `ExitCodeMapper.code(for:)` is the
    //     single source of truth used by every other subcommand, so we use it
    //     here too for consistency. This is the same mapping the constitution
    //     and other commands ship today.
    static func emit(
        response: XPCResponse,
        globals: GlobalOptions,
        requestedId: String
    ) throws {
        let envelopeRequestId = response.requestId
        let formatter = globals.outputMode.formatter(requestId: envelopeRequestId)

        if response.ok {
            guard let data = response.data else {
                let err = XPCError(
                    code: "xpc.decode_failure",
                    message: "Server returned ok=true but no data payload"
                )
                try formatter.emit(error: err)
                throw ExitCode(ExitCodeMapper.code(for: err))
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result: ContainerPutResult
            do {
                result = try decoder.decode(ContainerPutResult.self, from: data)
            } catch {
                let err = XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode ContainerPutResult: \(error.localizedDescription)"
                )
                try formatter.emit(error: err)
                throw ExitCode(ExitCodeMapper.code(for: err))
            }
            if !globals.isQuiet {
                try formatter.emit(success: result)
            }
            return
        }

        if let remoteError = response.error {
            try formatter.emit(error: remoteError)
            throw ExitCode(ExitCodeMapper.code(for: remoteError))
        }

        let err = XPCError(
            code: "xpc.decode_failure",
            message: "Server returned ok=false but no error payload"
        )
        try formatter.emit(error: err)
        throw ExitCode(ExitCodeMapper.code(for: err))
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
