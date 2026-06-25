import ArgumentParser
import AIDashCore
import Foundation

struct ContainerPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a container."
    )

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

    // MARK: - Global Flags

    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet = false

    // MARK: - Run

    func run() async throws {
        let resolvedDate = resolveDate(briefingDate)

        // Step 1: Local validation — fail fast, never round-trip invalid input.
        do {
            try SchemaValidator.validateContainerPut(
                id: id,
                title: title,
                order: order,
                layout: layout,
                style: style
            )
        } catch let error as XPCError {
            writeErrorToStderr(error)
            throw ExitCode(1)
        }

        // Step 2: Build params.
        guard let containerLayout = ContainerLayout(rawValue: layout) else {
            // Should not happen after validation, but avoid force-unwrap.
            let error = XPCError(
                code: "schema.unknown_container_layout",
                message: "Unknown layout '\(layout)'",
                field: "layout",
                got: layout,
                allowed: ContainerLayout.allCases.map(\.rawValue)
            )
            writeErrorToStderr(error)
            throw ExitCode(1)
        }

        guard let cardStyle = CardStyle(rawValue: style) else {
            let error = XPCError(
                code: "schema.unknown_card_style",
                message: "Unknown style '\(style)'",
                field: "style",
                got: style,
                allowed: CardStyle.allCases.map(\.rawValue)
            )
            writeErrorToStderr(error)
            throw ExitCode(1)
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

        // Step 3: Encode params and build XPC request.
        let paramsData: Data
        do {
            paramsData = try JSONEncoder().encode(params)
        } catch {
            let xpcError = XPCError(
                code: "schema.payload_decode_failed",
                message: "Failed to encode params: \(error.localizedDescription)"
            )
            writeErrorToStderr(xpcError)
            throw ExitCode(1)
        }

        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "container.put",
            params: paramsData
        )

        // Step 4: Send via XPC.
        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            writeErrorToStderr(error)
            throw ExitCode(2)
        } catch {
            let xpcError = XPCError(
                code: "xpc.connection_invalidated",
                message: "XPC transport failed: \(error.localizedDescription)"
            )
            writeErrorToStderr(xpcError)
            throw ExitCode(2)
        }

        // Step 5: Handle response.
        if response.ok {
            guard let data = response.data else {
                if !quiet { print("Container '\(id)' upserted.") }
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(ContainerPutResult.self, from: data)
            emitSuccess(result: result, requestId: response.requestId)
        } else if let error = response.error {
            throw error
        }
    }

    // MARK: - Output

    private func emitSuccess(result: ContainerPutResult, requestId: String) {
        if json {
            let formatter = ISO8601DateFormatter()
            let output: [String: Any] = [
                "ok": true,
                "data": [
                    "id": result.id,
                    "updatedAt": formatter.string(from: result.updatedAt),
                    "wasCreated": result.wasCreated,
                ],
                "requestId": requestId,
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } else if !quiet {
            let verb = result.wasCreated ? "Created" : "Updated"
            print("\(verb) container '\(result.id)'.")
        }
    }

    // MARK: - Helpers

    private func resolveDate(_ input: String) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        switch input.lowercased() {
        case "today":
            return formatter.string(from: Date())
        case "yesterday":
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return formatter.string(from: yesterday)
        default:
            return input
        }
    }

    private func writeErrorToStderr(_ error: XPCError) {
        var components: [String: Any] = [
            "ok": false,
            "error": buildErrorDict(error),
        ]
        // Suppress requestId since we haven't sent the request yet for local validation errors.
        _ = components // silence unused warning

        if let jsonData = try? JSONSerialization.data(
            withJSONObject: ["ok": false, "error": buildErrorDict(error)],
            options: [.sortedKeys]
        ),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            FileHandle.standardError.write(Data((jsonString + "\n").utf8))
        }
    }

    private func buildErrorDict(_ error: XPCError) -> [String: Any] {
        var dict: [String: Any] = [
            "code": error.code,
            "message": error.message,
        ]
        if let field = error.field { dict["field"] = field }
        if let got = error.got { dict["got"] = got }
        if let allowed = error.allowed { dict["allowed"] = allowed }
        if let cause = error.cause { dict["cause"] = cause }
        return dict
    }
}
