import Foundation

/// Wire projection of ScheduledJobAction. Job membership is resolved by the App registry.
public struct JobActionsAction: Codable, Sendable, Equatable {
    public struct ParentIssue: Codable, Sendable, Equatable {
        public let identifier: String
        public let title: String?
        public let url: String?

        public init(identifier: String, title: String? = nil, url: String? = nil) {
            self.identifier = identifier
            self.title = title
            self.url = url
        }
    }

    public struct Control: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case confirm, singleSelect, multiSelect, textInput, openURL
        }

        public let id: String
        public let kind: Kind
        public let title: String
        public let options: [String]
        public let maxLength: Int?
        public let url: String?

        public init(
            id: String,
            kind: Kind,
            title: String,
            options: [String] = [],
            maxLength: Int? = nil,
            url: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.options = options
            self.maxLength = maxLength
            self.url = url
        }

        public var effectiveMaxLength: Int { min(max(maxLength ?? 80, 0), 80) }

        private enum CodingKeys: String, CodingKey {
            case id, kind, title, label, options, maxLength, url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decode(Kind.self, forKey: .kind)
            title = try container.decodeIfPresent(String.self, forKey: .title)
                ?? (try container.decode(String.self, forKey: .label))
            options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
            maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
            url = try container.decodeIfPresent(String.self, forKey: .url)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(kind, forKey: .kind)
            try container.encode(title, forKey: .title)
            try container.encode(options, forKey: .options)
            try container.encodeIfPresent(maxLength, forKey: .maxLength)
            try container.encodeIfPresent(url, forKey: .url)
        }
    }

    public let id: String
    public let jobID: String
    public let createdAt: Date?
    public let title: String
    public let descriptionMd: String
    public var description: String { descriptionMd }
    public let status: String?
    public let source: String?
    public let priority: String?
    public let ref: String?
    public let url: String?
    public let subCategory: String?
    public let worthExtracting: Bool?
    public let labels: [String]
    public let project: String?
    public let parentIssue: ParentIssue?
    /// Optional canonical M2 topic supplied by the producer. Older producers omit it.
    public let topicID: String?
    public let controls: [Control]

    private struct SourcePayload: Decodable {
        let kind: String?
        let label: String?
        let url: String?
        let entityId: String?
        let headSha: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id, jobID, jobId, createdAt, title, description, descriptionMd
        case status, source, priority, ref, url, subCategory, worthExtracting
        case labels, project, parentIssue, topicID, topicId, topic_id, controls
    }

    public init(
        id: String, jobID: String, createdAt: Date? = nil,
        title: String, descriptionMd: String,
        status: String? = nil, source: String? = nil, priority: String? = nil,
        ref: String? = nil, url: String? = nil,
        subCategory: String? = nil, worthExtracting: Bool? = nil,
        labels: [String] = [], project: String? = nil, parentIssue: ParentIssue? = nil,
        topicID: String? = nil, controls: [Control]
    ) {
        self.id = id
        self.jobID = jobID
        self.createdAt = createdAt
        self.title = title
        self.descriptionMd = descriptionMd
        self.status = status
        self.source = source
        self.priority = priority
        self.ref = ref
        self.url = url
        self.subCategory = subCategory
        self.worthExtracting = worthExtracting
        self.labels = labels
        self.project = project
        self.parentIssue = parentIssue
        self.topicID = topicID
        self.controls = controls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
            ?? (try container.decode(String.self, forKey: .jobId))
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        if let md = try container.decodeIfPresent(String.self, forKey: .descriptionMd) {
            descriptionMd = md
        } else if let desc = try container.decodeIfPresent(String.self, forKey: .description) {
            descriptionMd = desc
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.descriptionMd,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected descriptionMd or description string."
                )
            )
        }
        status = try container.decodeIfPresent(String.self, forKey: .status)
        let sourcePayload: SourcePayload?
        if let sourceString = try? container.decode(String.self, forKey: .source) {
            source = sourceString
            sourcePayload = nil
        } else {
            sourcePayload = try container.decodeIfPresent(SourcePayload.self, forKey: .source)
            source = sourcePayload?.label
        }
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        ref = try container.decodeIfPresent(String.self, forKey: .ref) ?? sourcePayload?.entityId
        let explicitURL = try container.decodeIfPresent(String.self, forKey: .url)
        let decodedControls = try container.decode([Control].self, forKey: .controls)
        let controlURL = decodedControls.first(where: { $0.kind == .openURL })?.url
        url = explicitURL ?? sourcePayload?.url ?? controlURL
        subCategory = try container.decodeIfPresent(String.self, forKey: .subCategory)
        worthExtracting = try container.decodeIfPresent(Bool.self, forKey: .worthExtracting)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        project = try container.decodeIfPresent(String.self, forKey: .project)
        parentIssue = try container.decodeIfPresent(ParentIssue.self, forKey: .parentIssue)
        topicID = try container.decodeIfPresent(String.self, forKey: .topicID)
            ?? (try container.decodeIfPresent(String.self, forKey: .topicId))
            ?? (try container.decodeIfPresent(String.self, forKey: .topic_id))
        controls = decodedControls.filter { $0.kind != .openURL }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(jobID, forKey: .jobID)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(descriptionMd, forKey: .description)
        try container.encode(descriptionMd, forKey: .descriptionMd)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(ref, forKey: .ref)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(subCategory, forKey: .subCategory)
        try container.encodeIfPresent(worthExtracting, forKey: .worthExtracting)
        if !labels.isEmpty { try container.encode(labels, forKey: .labels) }
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(parentIssue, forKey: .parentIssue)
        try container.encodeIfPresent(topicID, forKey: .topicId)
        try container.encode(controls, forKey: .controls)
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
