import ArgumentParser
import Foundation
import Testing
import AIDashCore

@Suite("Job actions CLI")
struct JobActionsCommandTests {
    private var proposal: JobActionsPresentParams {
        JobActionsPresentParams(
            requestID: "00000000-0000-4000-8000-000000000001",
            jobID: "my-pr-supervisor", actionID: "synthetic", revision: String(repeating: "a", count: 64),
            responses: [.init(controlID: "confirm", value: "确认")]
        )
    }

    @Test("Snapshot sends a fixed XPC command and renders the existing success envelope")
    func snapshotSuccess() async throws {
        let payload = JobActionsSnapshot(capturedAt: Date(timeIntervalSince1970: 1000), present: true,
                                         entries: [], diagnostics: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(payload)
        let response = try await JobActionsCLI.snapshot { request in
            #expect(request.command == "job-actions.snapshot")
            #expect(request.params == Data("{}".utf8))
            return XPCResponse(requestId: request.requestId, appVersion: "test", ok: true, data: bytes, error: nil)
        }
        let snapshot = try JobActionsCLI.decode(response, as: JobActionsSnapshot.self)
        let object = try envelope(snapshot, requestID: response.requestId)
        #expect(object["ok"] as? Bool == true)
        #expect(object["requestId"] as? String == response.requestId)
        let data = try #require(object["data"] as? [String: Any])
        #expect(data["schemaVersion"] as? Int == 1)
        #expect(data["entries"] as? [String] == [])
    }

    @Test("Snapshot rejects unsupported CLI arguments and missing remote data")
    func snapshotFailure() {
        #expect(throws: (any Error).self) { try JobActionsSnapshotCommand.parse(["--confirm"]) }
        let response = XPCResponse(requestId: "test", appVersion: "test", ok: true, data: nil, error: nil)
        #expect(throws: XPCError.self) { try JobActionsCLI.decode(response, as: JobActionsSnapshot.self) }
    }

    @Test("Present sends only validated stdin fields and retains awaiting/native-required semantics")
    func presentSuccess() async throws {
        let expected = proposal
        let output = JobActionsPresentResult(requestID: expected.requestID)
        let bytes = try JSONEncoder().encode(output)
        let response = try await JobActionsCLI.present(JSONEncoder().encode(expected)) { request in
            #expect(request.command == "job-actions.present")
            let actual = try JobActionsValidation.decodePresent(request.params)
            #expect(actual == expected)
            return XPCResponse(requestId: request.requestId, appVersion: "test", ok: true, data: bytes, error: nil)
        }
        let result = try JobActionsCLI.decode(response, as: JobActionsPresentResult.self)
        let object = try envelope(result, requestID: response.requestId)
        let data = try #require(object["data"] as? [String: Any])
        #expect(object["ok"] as? Bool == true)
        #expect(data["status"] as? String == "awaitingNativeConfirmation")
        #expect(data["acknowledgement"] is NSNull)
        #expect(try JobActionsPresentCommand.parse(["--stdin"]).stdin)
    }

    @Test("Extra or oversized proposal fields reject before transport; argv cannot select paths or callbacks")
    func presentFailure() async throws {
        for bytes in [Data(#"{"confirm":true}"#.utf8), Data(repeating: 32, count: 16385)] {
            do {
                _ = try await JobActionsCLI.present(bytes) { _ in
                    Issue.record("Invalid stdin reached XPC")
                    throw XPCError(code: "test.unexpected", message: "No transport expected")
                }
                Issue.record("Invalid proposal accepted")
            } catch let error as XPCError {
                #expect(error.code == "schema.invalid-request")
            }
        }
        #expect(throws: (any Error).self) { try JobActionsPresentCommand.parse(["--stdin", "--confirm"]) }
        #expect(throws: (any Error).self) { try JobActionsPresentCommand.parse(["--path", "/synthetic"]) }
    }

    @Test("Stdin handles fragmented multibyte input and exact byte limit; oversize reads are rejected")
    func boundedStdin() throws {
        let input = try JSONEncoder().encode(proposal)
        var remaining = Array(input)
        let collected = try JobActionsCLI.readInput { _ in
            guard !remaining.isEmpty else { return nil }
            let next = Data(remaining.prefix(3))
            remaining.removeFirst(min(3, remaining.count))
            return next
        }
        #expect(collected == input)
        var chunks = [Data(repeating: 32, count: 16384)]
        #expect(try JobActionsCLI.readInput { _ in chunks.isEmpty ? nil : chunks.removeFirst() }.count == 16384)
        #expect(throws: XPCError.self) {
            try JobActionsCLI.readInput { _ in Data(repeating: 32, count: 16385) }
        }
    }

    @Test("Remote errors stay remote and preserve safe error envelopes")
    func remoteFailure() async throws {
        let response = try await JobActionsCLI.snapshot { request in
            XPCResponse(requestId: request.requestId, appVersion: "test", ok: false, data: nil,
                        error: XPCError(code: "job-actions.bridge-unavailable", message: "Unavailable", cause: "private"))
        }
        #expect(!response.ok)
        let error = try #require(response.error)
        let bytes = try JSONEncoder().encode(CLIErrorEnvelope(from: error, requestId: response.requestId))
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let body = try #require(object["error"] as? [String: Any])
        #expect(body["requestId"] as? String == response.requestId)
        #expect(body["cause"] == nil)
    }

    private func envelope(_ data: any Encodable, requestID: String) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try #require(JSONSerialization.jsonObject(
            with: encoder.encode(CLISuccessEnvelope(data: data, requestId: requestID))
        ) as? [String: Any])
    }
}
