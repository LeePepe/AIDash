import AIDashCore
import Foundation

/// Emits structured JSON success/error envelopes.
enum JSONOutput {

    /// Write a success envelope to stdout.
    static func writeSuccess<T: Encodable>(_ data: T, requestId: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let dataBytes = try encoder.encode(data)
        let envelope: [String: Any] = [
            "ok": true,
            "data": try JSONSerialization.jsonObject(with: dataBytes),
            "requestId": requestId,
        ]
        let outputData = try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(outputData)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// Write an error envelope to stderr (always JSON per contract).
    static func writeError(_ error: XPCError, requestId: String) {
        var envelope: [String: Any] = [
            "ok": false,
            "error": buildErrorDict(error),
            "requestId": requestId,
        ]
        _ = envelope.removeValue(forKey: "_") // suppress warning
        guard let data = try? JSONSerialization.data(
            withJSONObject: envelope,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private static func buildErrorDict(_ error: XPCError) -> [String: Any] {
        var dict: [String: Any] = [
            "code": error.code,
            "message": error.message,
        ]
        if let field = error.field { dict["field"] = field }
        if let got = error.got { dict["got"] = got }
        if let allowed = error.allowed { dict["allowed"] = allowed }
        return dict
    }
}
