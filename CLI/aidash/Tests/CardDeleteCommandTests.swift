import Foundation
import Testing
import AIDashCore
import ArgumentParser

/// Tests for `aidash card delete` (T176).
///
/// Mirrors `ContainerDeleteCommandTests`. Reuses `GlobalOptions.test` and the
/// `captureStdout` FD-redirect helper from `ContainerPutCommandTests` (same
/// test target/module).
@Suite("CardDeleteCommand")
struct CardDeleteCommandTests {

    static let validID = "22222222-2222-2222-2222-222222222222"

    // MARK: - Argument Parsing

    @Test("parses required --id flag")
    func parsesID() throws {
        let cmd = try CardDeleteCommand.parse(["--id", Self.validID])
        #expect(cmd.id == Self.validID)
        #expect(cmd.globals.json == false)
        #expect(cmd.globals.quiet == false)
    }

    @Test("parses global --json/--quiet flags")
    func parsesGlobals() throws {
        let cmd = try CardDeleteCommand.parse(["--id", Self.validID, "--json", "--quiet"])
        #expect(cmd.globals.json == true)
        #expect(cmd.globals.quiet == true)
    }

    @Test("missing --id is a parse error")
    func missingIDFails() {
        #expect(throws: (any Error).self) {
            _ = try CardDeleteCommand.parse([])
        }
    }

    // MARK: - Local validation

    @Test("validateCardDelete accepts a well-formed UUID")
    func acceptsValidUUID() throws {
        try SchemaValidator.validateCardDelete(id: Self.validID)
    }

    @Test("validateCardDelete rejects an empty id")
    func rejectsEmptyID() {
        #expect(throws: XPCError.self) {
            try SchemaValidator.validateCardDelete(id: "")
        }
    }

    @Test("validateCardDelete rejects a malformed UUID")
    func rejectsMalformedUUID() {
        do {
            try SchemaValidator.validateCardDelete(id: "nope")
            Issue.record("Expected XPCError")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "id")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - XPC request envelope

    @Test("buildXPCRequest packs CardDeleteParams as the documented card.delete envelope")
    func buildsDeleteRequest() throws {
        let params = CardDeleteParams(id: Self.validID)
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: "req-1",
            cliVersion: "1.0.0",
            command: "card.delete",
            params: paramsData
        )
        #expect(request.command == "card.delete")
        let decoded = try JSONDecoder().decode(CardDeleteParams.self, from: request.params)
        #expect(decoded.id == Self.validID)
    }

    // MARK: - emit — success path

    @Test("card delete success emits {ok:true, requestId} JSON envelope")
    func successEnvelopeJSON() throws {
        let data = try JSONEncoder().encode(CardDeleteResult())
        let response = XPCResponse(
            requestId: "req-ok",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let stdout = try captureStdout {
            try CardDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
        }
        let json = try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == true)
        #expect(json?["requestId"] as? String == "req-ok")
    }

    @Test("card delete honors --quiet (no stdout on success)")
    func quietSuppressesStdout() throws {
        let response = XPCResponse(
            requestId: "req-q",
            appVersion: "test",
            ok: true,
            data: nil,
            error: nil
        )
        let stdout = try captureStdout {
            try CardDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: true)
            )
        }
        #expect(stdout.isEmpty)
    }

    // MARK: - emit — remote error re-throw

    @Test("card delete not_found re-throws XPCError verbatim")
    func notFoundRethrows() throws {
        let errorBody = XPCError(
            code: "card.not_found",
            message: "No card found with id 'x'"
        )
        let response = XPCResponse(
            requestId: "req-nf",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        do {
            try CardDeleteCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be thrown")
        } catch let error as XPCError {
            #expect(error.code == "card.not_found")
        }
    }

    // MARK: - Exit-code mapping

    @Test("card.not_found maps to exit 3")
    func notFoundMapsToThree() {
        #expect(ExitCodeMapper.code(for: XPCError(code: "card.not_found", message: "x")) == 3)
    }
}
