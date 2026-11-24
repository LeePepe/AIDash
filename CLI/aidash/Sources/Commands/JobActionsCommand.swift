import ArgumentParser
import Foundation
import AIDashCore

struct JobActionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "job-actions",
        abstract: "Read registered action items or stage native AIDash review. Never writes user events.",
        subcommands: [JobActionsSnapshotCommand.self, JobActionsPresentCommand.self]
    )
}

struct JobActionsSnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Return current registered actions, revisions, receipt states and source diagnostics."
    )

    @OptionGroup var globals: GlobalOptions

    /// Throws local transport/decode errors. Remote failures retain their request ID and exit 3.
    func run() async throws {
        let response = try await JobActionsCLI.snapshot()
        try JobActionsCLI.emit(response, as: JobActionsSnapshot.self)
    }
}

struct JobActionsPresentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "present",
        abstract: "Stage a proposal for native confirmation; this does not record a receipt.",
        discussion: """
        Requires --stdin with one UTF-8 JSON object (at most 16 KiB):
        requestID (UUID), jobID, actionID, revision (snapshot SHA256), responses
        [{controlID,value}]. No extra fields. Supply every declared control once.
        Confirm value is 确认; selections must match declared options. Multi-select
        values are Swift-sorted comma-joined options. Text is at most 80 graphemes
        and the declaration's effective maxLength. Only a native App tap can save.
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Read the bounded proposal JSON from standard input. Required.")
    var stdin = false

    /// Throws `schema.invalid-request` without --stdin, validation errors or local XPC failures.
    func run() async throws {
        guard stdin else {
            throw XPCError(code: "schema.invalid-request", message: "job-actions present requires --stdin.")
        }
        let input = try JobActionsCLI.readInput { limit in try FileHandle.standardInput.read(upToCount: limit) }
        let response = try await JobActionsCLI.present(input)
        try JobActionsCLI.emit(response, as: JobActionsPresentResult.self)
    }
}

/// Thin, injected XPC operations; never resolves a home directory or opens any event store.
enum JobActionsCLI {
    typealias Execute = @Sendable (XPCRequest) async throws -> XPCResponse

    /// Throws local XPC errors; remote responses are returned unchanged.
    static func snapshot(
        execute: Execute = { try await XPCClient().execute($0) }
    ) async throws -> XPCResponse {
        try await execute(request(command: "job-actions.snapshot", params: Data("{}".utf8)))
    }

    /// Throws validation errors before transport; remote responses are returned unchanged.
    static func present(
        _ input: Data, execute: Execute = { try await XPCClient().execute($0) }
    ) async throws -> XPCResponse {
        let params = try JobActionsValidation.decodePresent(input)
        return try await execute(request(command: "job-actions.present", params: JSONEncoder().encode(params)))
    }

    /// Reads through EOF, including short pipe reads. Throws on I/O failure or more than 16 KiB.
    static func readInput(read: (Int) throws -> Data?) throws -> Data {
        var result = Data()
        do {
            while let chunk = try read(JobActionsValidation.maximumRequestBytes + 1 - result.count), !chunk.isEmpty {
                result.append(chunk)
                guard result.count <= JobActionsValidation.maximumRequestBytes else {
                    throw XPCError(code: "schema.invalid-request", message: "Action proposal exceeds 16 KiB.")
                }
            }
        } catch let error as XPCError {
            throw error
        } catch {
            throw XPCError(code: "schema.invalid-request", message: "Unable to read action proposal from stdin.")
        }
        return result
    }

    /// Throws local decode errors. Remote failures always use stderr JSON and exit 3.
    static func emit<T: Codable>(_ response: XPCResponse, as type: T.Type) throws {
        if !response.ok {
            guard let error = response.error else {
                throw XPCError(code: "xpc.decode_failure", message: "Bridge returned no error payload.")
            }
            try JSONOutput().emit(error: error, requestId: response.requestId)
            Darwin.exit(3)
        }
        let result = try decode(response, as: type)
        // Bridge payloads are essential output, like events pull; no human-only fallback.
        try JSONOutput().emit(success: result, requestId: response.requestId)
    }

    /// Throws `xpc.decode_failure` for absent or invalid typed result bytes.
    static func decode<T: Decodable>(_ response: XPCResponse, as type: T.Type) throws -> T {
        guard let data = response.data else {
            throw XPCError(code: "xpc.decode_failure", message: "Bridge returned no result payload.")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            throw XPCError(code: "xpc.decode_failure", message: "Unable to decode the bridge result.")
        }
    }

    private static func request(command: String, params: Data) -> XPCRequest {
        XPCRequest(requestId: UUID().uuidString, cliVersion: "1.0.0", command: command, params: params)
    }
}
