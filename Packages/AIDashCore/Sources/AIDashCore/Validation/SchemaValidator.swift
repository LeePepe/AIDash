import Foundation

/// Pre-dispatch schema validator for XPC commands.
/// All methods are pure, stateless, and designed for < 1ms execution.
public struct SchemaValidator {

    private static let maxPayloadBytes = 256 * 1024

    // MARK: - Public API

    public static func validateBriefingPut(date: String, generatedBy: String) throws {
        try requireNonEmpty(date, field: "date")
        try requireNonEmpty(generatedBy, field: "generatedBy")
        try requireValidDate(date)
    }

    public static func validateBriefingPublish(date: String) throws {
        try requireNonEmpty(date, field: "date")
        try requireValidDate(date)
    }

    public static func validateBriefingGet(date: String) throws {
        try requireNonEmpty(date, field: "date")
        try requireValidDate(date)
    }

    public static func validateContainerDelete(id: String) throws {
        try requireNonEmpty(id, field: "id")
        try requireValidUUID(id, field: "id")
    }

    public static func validateCardDelete(id: String) throws {
        try requireNonEmpty(id, field: "id")
        try requireValidUUID(id, field: "id")
    }

    public static func validateContainerPut(
        id: String,
        title: String,
        order: Int,
        layout: String,
        style: String
    ) throws {
        try requireNonEmpty(id, field: "id")
        try requireNonEmpty(title, field: "title")
        try requireNonEmpty(layout, field: "layout")
        try requireNonEmpty(style, field: "style")
        try requireValidUUID(id, field: "id")
        try requireValidEnum(layout, field: "layout", type: ContainerLayout.self,
                             errorCode: "schema.unknown_container_layout")
        try requireValidEnum(style, field: "style", type: CardStyle.self,
                             errorCode: "schema.unknown_card_style")
    }

    public static func validateCardPut(
        containerId: String,
        id: String,
        type: String,
        size: String,
        style: String,
        payload: Data
    ) throws {
        try requireNonEmpty(containerId, field: "containerId")
        try requireNonEmpty(id, field: "id")
        try requireNonEmpty(type, field: "type")
        try requireNonEmpty(size, field: "size")
        try requireNonEmpty(style, field: "style")
        try requireValidUUID(containerId, field: "containerId")
        try requireValidUUID(id, field: "id")

        guard let cardType = CardType(rawValue: type) else {
            throw XPCError(
                code: "schema.unknown_card_type",
                message: "Unknown card type '\(type)'",
                field: "type",
                got: type,
                allowed: CardType.allCases.map(\.rawValue)
            )
        }

        try requireValidEnum(size, field: "size", type: CardSize.self,
                             errorCode: "schema.unknown_card_size")
        try requireValidEnum(style, field: "style", type: CardStyle.self,
                             errorCode: "schema.unknown_card_style")
        try validatePayloadSize(payload)

        do {
            try cardType.validate(payload)
        } catch let xpcError as XPCError where xpcError.code == "schema.payload_decode_failed" {
            // Invariant violation — already has the correct code and field.
            throw xpcError
        } catch let decodingError as DecodingError {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "Payload JSON does not match \(type) schema",
                field: Self.firstFailingKey(from: decodingError),
                cause: decodingError.localizedDescription
            )
        } catch {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "Payload JSON does not match \(type) schema",
                field: "payload",
                cause: error.localizedDescription
            )
        }
    }

    public static func validateUserEvent(
        id: String,
        device: String,
        cardId: String,
        action: String
    ) throws {
        try requireNonEmpty(id, field: "id")
        try requireNonEmpty(device, field: "device")
        try requireNonEmpty(cardId, field: "cardId")
        try requireNonEmpty(action, field: "action")
        try requireValidUUID(id, field: "id")
        try requireValidUUID(cardId, field: "cardId")
        try requireValidEnum(action, field: "action", type: UserEventAction.self,
                             errorCode: "schema.unknown_user_event_action")
    }

    public static func validatePayloadSize(_ data: Data) throws {
        guard data.count <= maxPayloadBytes else {
            throw XPCError(
                code: "schema.payload_too_large",
                message: "Payload size \(data.count) bytes exceeds 256 KB limit",
                field: "payload",
                got: "\(data.count)"
            )
        }
    }

    // MARK: - Private Helpers

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.isEmpty else {
            throw XPCError(
                code: "schema.missing_required_field",
                message: "Required field '\(field)' is empty",
                field: field
            )
        }
    }

    private static func requireValidUUID(_ value: String, field: String) throws {
        guard UUID(uuidString: value) != nil else {
            throw XPCError(
                code: "schema.invalid_uuid",
                message: "Field '\(field)' is not a valid UUID",
                field: field,
                got: value
            )
        }
    }

    private static func requireValidDate(_ value: String) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        guard formatter.date(from: value) != nil else {
            throw XPCError(
                code: "schema.invalid_date",
                message: "Date '\(value)' is not in YYYY-MM-DD format",
                field: "date",
                got: value
            )
        }
    }

    private static func requireValidEnum<E: RawRepresentable & CaseIterable>(
        _ value: String,
        field: String,
        type: E.Type,
        errorCode: String
    ) throws where E.RawValue == String {
        guard E(rawValue: value) != nil else {
            throw XPCError(
                code: errorCode,
                message: "Unknown value '\(value)' for field '\(field)'",
                field: field,
                got: value,
                allowed: E.allCases.map(\.rawValue)
            )
        }
    }

    private static func firstFailingKey(from error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return key.stringValue
        case .valueNotFound(_, let context):
            return context.codingPath.last?.stringValue ?? "payload"
        case .typeMismatch(_, let context):
            return context.codingPath.last?.stringValue ?? "payload"
        case .dataCorrupted(let context):
            return context.codingPath.last?.stringValue ?? "payload"
        @unknown default:
            return "payload"
        }
    }
}
