import Foundation
import CryptoKit

/// Validation shared by the public CLI and App. No event writes or UI operations.
public enum JobActionsValidation {
    public static let maximumRequestBytes = 16 * 1024

    /// Throws `schema.invalid-request` for invalid UTF-8/JSON, extra fields or oversized input,
    /// and `schema.invalid-response` for malformed/duplicate response fields.
    public static func decodePresent(_ data: Data) throws -> JobActionsPresentParams {
        guard data.count <= maximumRequestBytes, String(data: data, encoding: .utf8) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["requestID", "jobID", "actionID", "revision", "responses"]),
              let responses = object["responses"] as? [[String: Any]],
              responses.allSatisfy({ Set($0.keys) == Set(["controlID", "value"]) }),
              let params = try? JSONDecoder().decode(JobActionsPresentParams.self, from: data) else {
            throw failure("invalid-request")
        }
        try validatePresent(params)
        return params
    }

    /// Throws `schema.invalid-request` or `schema.invalid-response`; values are never truncated.
    public static func validatePresent(_ params: JobActionsPresentParams) throws {
        guard params.requestID.count == 36, UUID(uuidString: params.requestID) != nil,
              validID(params.jobID), validID(params.actionID),
              params.revision.count == 64,
              params.revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw failure("invalid-request")
        }
        guard !params.responses.isEmpty, params.responses.count <= 32,
              Set(params.responses.map(\.controlID)).count == params.responses.count,
              params.responses.allSatisfy({ validID($0.controlID) && $0.value.count <= 80 }) else {
            throw failure("invalid-response")
        }
    }

    /// Throws `schema.invalid-response` for unsupported producer declarations or incomplete values.
    public static func validateResponses(_ responses: [JobActionsResponse], for action: JobActionsAction) throws {
        try validateAction(action)
        guard responses.count == action.controls.count,
              Set(responses.map(\.controlID)).count == responses.count else {
            throw failure("invalid-response")
        }
        let values = Dictionary(uniqueKeysWithValues: responses.map { ($0.controlID, $0.value) })
        guard Set(values.keys) == Set(action.controls.map(\.id)) else { throw failure("invalid-response") }
        for control in action.controls {
            guard let value = values[control.id], value.count <= 80 else { throw failure("invalid-response") }
            switch control.kind {
            case .confirm:
                guard value == "确认" else { throw failure("invalid-response") }
            case .singleSelect:
                guard control.options.contains(value) else { throw failure("invalid-response") }
            case .multiSelect:
                let selected = value.isEmpty ? [] : value.components(separatedBy: ",")
                guard Set(selected).count == selected.count,
                      selected.allSatisfy({ control.options.contains($0) }),
                      selected.sorted().joined(separator: ",") == value else { throw failure("invalid-response") }
            case .textInput:
                guard value.count <= control.effectiveMaxLength else { throw failure("invalid-response") }
            }
        }
    }

    /// Throws `schema.invalid-response` for declarations that cannot be represented safely.
    public static func validateAction(_ action: JobActionsAction) throws {
        guard validID(action.id), validID(action.jobID),
              !action.title.isEmpty, action.title.count <= 512,
              action.descriptionMd.utf8.count <= 32 * 1024,
              !action.controls.isEmpty, action.controls.count <= 32,
              Set(action.controls.map(\.id)).count == action.controls.count else {
            throw failure("invalid-response")
        }
        for control in action.controls {
            guard validID(control.id), !control.title.isEmpty, control.title.count <= 512,
                  control.options.count <= 64,
                  Set(control.options).count == control.options.count,
                  control.options.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else {
                throw failure("invalid-response")
            }
            switch control.kind {
            case .singleSelect:
                guard !control.options.isEmpty else { throw failure("invalid-response") }
            case .multiSelect:
                guard !control.options.isEmpty,
                      control.options.allSatisfy({ !$0.contains(",") }) else { throw failure("invalid-response") }
            case .confirm, .textInput:
                break
            }
        }
    }

    /// SHA256 of sorted-key canonical JSON, including raw limits and full timestamp precision.
    /// Throws `EncodingError` if the canonical action cannot be encoded.
    public static func revision(for action: JobActionsAction) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try SHA256.hash(data: encoder.encode(action)).map { String(format: "%02x", $0) }.joined()
    }

    /// Only exact job/action receipts with decodable response JSON can acknowledge an entry.
    public static func acknowledgement(in events: [UserEvent], for action: JobActionsAction) -> UserEvent? {
        events.filter { event in
            guard event.action == .acknowledgeJobAction,
                  event.cardId == "scheduled-pulse/\(action.jobID)",
                  event.cardType == "scheduledPulse",
                  let ref = event.itemRef, let separator = ref.firstIndex(of: "|"),
                  String(ref[..<separator]) == action.id,
                  let responses = try? JSONDecoder().decode(
                    [JobActionsResponse].self, from: Data(ref[ref.index(after: separator)...].utf8)
                  ) else { return false }
            return !responses.isEmpty && responses.count <= 32
                && Set(responses.map(\.controlID)).count == responses.count
                && responses.allSatisfy { validID($0.controlID) && $0.value.count <= 80 }
        }.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id < $1.id
        }.first
    }

    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && !value.contains("|") && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func failure(_ reason: String) -> XPCError {
        XPCError(code: "schema.\(reason)", message: "Invalid action proposal (\(reason)).")
    }
}
