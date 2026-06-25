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

    // MARK: - Global Flags (per CLI contract, available on all leaf commands)

    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet = false

    // MARK: - Run

    func run() async throws {
        // Step 1: Resolve and validate date locally.
        let resolvedDate = resolveDate(briefingDate)
        do {
            try validateDate(resolvedDate)
        } catch let error as XPCError {
            writeErrorToStderr(error, requestId: nil)
            throw ExitCode(1)
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
            writeErrorToStderr(error, requestId: nil)
            throw ExitCode(1)
        }

        // Step 3: Build params.
        guard let containerLayout = ContainerLayout(rawValue: layout) else {
            let error = XPCError(
                code: "schema.unknown_container_layout",
                message: "Unknown layout '\(layout)'",
                field: "layout",
                got: layout,
                allowed: ContainerLayout.allCases.map(\.rawValue)
            )
            writeErrorToStderr(error, requestId: nil)
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
            writeErrorToStderr(error, requestId: nil)
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

        // Step 4: Encode params and build XPC request.
        let requestId = UUID().uuidString
        let paramsData: Data
        do {
            paramsData = try JSONEncoder().encode(params)
        } catch {
            let xpcError = XPCError(
                code: "schema.payload_decode_failed",
                message: "Failed to encode params: \(error.localizedDescription)"
            )
            writeErrorToStderr(xpcError, requestId: requestId)
            throw ExitCode(1)
        }

        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "container.put",
            params: paramsData
        )

        // Step 5: Send via XPC.
        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            writeErrorToStderr(error, requestId: requestId)
            throw ExitCode(2)
        } catch {
            let xpcError = XPCError(
                code: "xpc.connection_invalidated",
                message: "XPC transport failed: \(error.localizedDescription)"
            )
            writeErrorToStderr(xpcError, requestId: requestId)
            throw ExitCode(2)
        }

        // Step 6: Handle response.
        if response.ok {
            guard let data = response.data else {
                if !quiet { print("Container '\(id)' upserted.") }
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(ContainerPutResult.self, from: data)
            emitSuccess(result: result, requestId: response.requestId)
        } else if let remoteError = response.error {
            let exitCode = Self.mapErrorToExitCode(remoteError)
            writeErrorToStderr(remoteError, requestId: response.requestId)
            throw ExitCode(exitCode)
        }
    }

    // MARK: - Exit Code Mapping

    /// Maps remote error codes to CLI exit codes per the contract:
    /// - schema.* → 1 (local validation, should not reach here but possible from app)
    /// - xpc.* → 2 (transport failure)
    /// - briefing.* / container.* / card.* / cloudkit.* / internal.* → 3 (app-side error)
    static func mapErrorToExitCode(_ error: XPCError) -> Int32 {
        let prefix = error.code.split(separator: ".").first.map(String.init) ?? ""
        switch prefix {
        case "schema":
            return 1
        case "xpc":
            return 2
        default:
            return 3
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

    /// Validate resolved date is a valid YYYY-MM-DD string.
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

    /// Write the standard JSON error envelope to stderr, including requestId when available.
    private func writeErrorToStderr(_ error: XPCError, requestId: String?) {
        var envelope: [String: Any] = [
            "ok": false,
            "error": buildErrorDict(error),
        ]
        if let requestId {
            envelope["requestId"] = requestId
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]),
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
