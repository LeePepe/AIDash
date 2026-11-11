import Foundation

/// Wire projection of ScheduledJobAction. Job membership is resolved by the App registry.
public struct JobActionsAction: Codable, Sendable, Equatable {
    public struct Control: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case confirm, singleSelect, multiSelect, textInput
        }

        public let id: String
        public let kind: Kind
        public let title: String
        public let options: [String]
        public let maxLength: Int?

        public init(id: String, kind: Kind, title: String, options: [String] = [], maxLength: Int? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.options = options
            self.maxLength = maxLength
        }

        public var effectiveMaxLength: Int { min(max(maxLength ?? 80, 0), 80) }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decode(Kind.self, forKey: .kind)
            title = try container.decode(String.self, forKey: .title)
            options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
            maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        }
    }

    public let id: String
    public let jobID: String
    public let createdAt: Date?
    public let title: String
    public let descriptionMd: String
    public let controls: [Control]

    public init(
        id: String, jobID: String, createdAt: Date? = nil,
        title: String, descriptionMd: String, controls: [Control]
    ) {
        self.id = id
        self.jobID = jobID
        self.createdAt = createdAt
        self.title = title
        self.descriptionMd = descriptionMd
        self.controls = controls
    }
}

public struct JobActionsResponse: Codable, Sendable, Equatable {
    public let controlID: String
    public let value: String

    /// Preserves the proposed value verbatim; validation rejects rather than truncates.
    public init(controlID: String, value: String) {
        self.controlID = controlID
        self.value = value
    }
}

public struct JobActionsPresentParams: Codable, Sendable, Equatable {
    public let requestID: String
    public let jobID: String
    public let actionID: String
    public let revision: String
    public let responses: [JobActionsResponse]

    public init(
        requestID: String, jobID: String, actionID: String,
        revision: String, responses: [JobActionsResponse]
    ) {
        self.requestID = requestID
        self.jobID = jobID
        self.actionID = actionID
        self.revision = revision
        self.responses = responses
    }
}

public struct JobActionsDiagnostic: Codable, Sendable {
    public let code: String
    public let jobID: String?

    public init(code: String, jobID: String? = nil) {
        self.code = code
        self.jobID = jobID
    }
}

public struct JobActionsSnapshot: Codable, Sendable {
    public struct Capabilities: Codable, Sendable {
        public let present: Bool
        public let nativeConfirmationRequired: Bool

        public init(present: Bool) {
            self.present = present
            self.nativeConfirmationRequired = true
        }
    }

    public struct Entry: Codable, Sendable {
        public let action: JobActionsAction
        public let revision: String
        public let acknowledgement: UserEvent?

        public init(action: JobActionsAction, revision: String, acknowledgement: UserEvent?) {
            self.action = action
            self.revision = revision
            self.acknowledgement = acknowledgement
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .action)
            try container.encode(revision, forKey: .revision)
            try container.encode(acknowledgement, forKey: .acknowledgement)
        }
    }

    public let schemaVersion: Int
    public let capturedAt: Date
    public let capabilities: Capabilities
    public let entries: [Entry]
    public let diagnostics: [JobActionsDiagnostic]

    public init(capturedAt: Date, present: Bool, entries: [Entry], diagnostics: [JobActionsDiagnostic]) {
        self.schemaVersion = 1
        self.capturedAt = capturedAt
        self.capabilities = Capabilities(present: present)
        self.entries = entries
        self.diagnostics = diagnostics
    }
}

public struct JobActionsPresentResult: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case awaitingNativeConfirmation
        case acknowledged
    }

    public let requestID: String
    public let status: Status
    public let acknowledgement: UserEvent?

    public init(requestID: String, acknowledgement: UserEvent? = nil) {
        self.requestID = requestID
        self.status = acknowledgement == nil ? .awaitingNativeConfirmation : .acknowledged
        self.acknowledgement = acknowledgement
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(status, forKey: .status)
        try container.encode(acknowledgement, forKey: .acknowledgement)
    }
}
