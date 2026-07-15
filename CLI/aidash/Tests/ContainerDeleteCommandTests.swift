import Foundation
import Testing
import AIDashCore
import ArgumentParser

/// Tests for `aidash container delete` (T175).
///
/// Mirrors the structure of `ContainerPutCommandTests` / `CardPutCommandTests`:
///   1. Argument parsing.
///   2. Local validation (`SchemaValidator.validateContainerDelete`).
///   3. XPC request envelope construction (matches `container.delete` contract).
///   4. Subcommand-level `emit` success path.
///   5. Remote-error re-throw + exit-code mapping.
///
/// Reuses `GlobalOptions.test` and the `captureStdout`/`captureStderr` FD-redirect
/// helpers defined in `ContainerPutCommandTests` (same test target/module).
@Suite("ContainerDeleteCommand")
struct ContainerDeleteCommandTests {

    static let validID = "11111111-1111-1111-1111-111111111111"

    // MARK: - Argument Parsing

    @Test("parses required --id flag")
    func parsesID() throws {
        let cmd = try ContainerDeleteCommand.parse(["--id", Self.validID])
        #expect(cmd.id == Self.validID)
        #expect(cmd.globals.json == false)
        #expect(cmd.globals.quiet == false)
    }

    @Test("parses global --json/--quiet flags")
    func parsesGlobals() throws {
        let cmd = try ContainerDeleteCommand.parse(["--id", Self.validID, "--json", "--quiet"])
        #expect(cmd.globals.json == true)
        #expect(cmd.globals.quiet == true)
    }

    @Test("missing --id is a parse error")
    func missingIDFails() {
        #expect(throws: (any Error).self) {
            _ = try ContainerDeleteCommand.parse([])
        }
    }

    // MARK: - Local validation

    @Test("validateContainerDelete accepts a well-formed UUID")
    func acceptsValidUUID() throws {
        try SchemaValidator.validateContainerDelete(id: Self.validID)
    }

    @Test("validateContainerDelete rejects an empty id")
    func rejectsEmptyID() {
        #expect(throws: XPCError.self) {
            try SchemaValidator.validateContainerDelete(id: "")
        }
    }

    @Test("validateContainerDelete rejects a malformed UUID")
    func rejectsMalformedUUID() {
        do {
            try SchemaValidator.validateContainerDelete(id: "not-a-uuid")
            Issue.record("Expected XPCError")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "id")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - XPC request envelope

    @Test("buildXPCRequest packs ContainerDeleteParams as the documented container.delete envelope")
    func buildsDeleteRequest() throws {
        let params = ContainerDeleteParams(id: Self.validID)
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: "req-1",
            cliVersion: "1.0.0",
            command: "container.delete",
            params: paramsData
        )
        #expect(request.command == "container.delete")
        let decoded = try JSONDecoder().decode(ContainerDeleteParams.self, from: request.params)
        #expect(decoded.id == Self.validID)
    }

    // MARK: - emit — success path

    @Test("container delete success emits {ok:true, requestId} JSON envelope")
    func successEnvelopeJSON() throws {
        let data = try JSONEncoder().encode(ContainerDeleteResult())
        let response = XPCResponse(
            requestId: "req-ok",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let stdout = try captureStdout {
            try ContainerDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
        }
        let json = try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == true)
        #expect(json?["requestId"] as? String == "req-ok")
    }

    @Test("container delete success tolerates a bodyless ok=true (empty result type)")
    func successBodylessOK() throws {
        let response = XPCResponse(
            requestId: "req-empty",
            appVersion: "test",
            ok: true,
            data: nil,
            error: nil
        )
        let stdout = try captureStdout {
            try ContainerDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
        }
        let json = try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == true)
    }

    @Test("container delete honors --quiet (no stdout on success)")
    func quietSuppressesStdout() throws {
        let response = XPCResponse(
            requestId: "req-q",
            appVersion: "test",
            ok: true,
            data: nil,
            error: nil
        )
        let stdout = try captureStdout {
            try ContainerDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: true)
            )
        }
        #expect(stdout.isEmpty)
    }

    // MARK: - emit — remote error re-throw

    @Test("container delete not_found re-throws XPCError verbatim")
    func notFoundRethrows() throws {
        let errorBody = XPCError(
            code: "container.not_found",
            message: "No container found with id 'x'"
        )
        let response = XPCResponse(
            requestId: "req-nf",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        do {
            try ContainerDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be thrown")
        } catch let error as XPCError {
            #expect(error.code == "container.not_found")
        }
    }

    @Test("container delete ok=false with no error payload throws xpc.decode_failure")
    func bodylessErrorThrowsDecodeFailure() throws {
        let response = XPCResponse(
            requestId: "req-bad",
            appVersion: "test",
            ok: false,
            data: nil,
            error: nil
        )
        do {
            try ContainerDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError")
        } catch let error as XPCError {
            #expect(error.code == "xpc.decode_failure")
        }
    }

    // MARK: - Exit-code mapping

    @Test("container.not_found maps to exit 3")
    func notFoundMapsToThree() {
        #expect(ExitCodeMapper.code(for: XPCError(code: "container.not_found", message: "x")) == 3)
    }

    @Test("schema.invalid_uuid maps to exit 1")
    func schemaMapsToOne() {
        #expect(ExitCodeMapper.code(for: XPCError(code: "schema.invalid_uuid", message: "x")) == 1)
    }

    @Test("xpc.app_unavailable maps to exit 2")
    func xpcMapsToTwo() {
        #expect(ExitCodeMapper.code(for: XPCError(code: "xpc.app_unavailable", message: "x")) == 2)
    }
}
