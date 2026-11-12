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
    public var description: String { descriptionMd }
    public let status: String?
    public let source: String?
    public let priority: String?
    public let ref: String?
    public let url: String?
    public let domain: String?
    public let topicKey: String?
    public let originRef: String?
    public let revision: String?
    public let whyNow: String?
    public let sourceURI: String?
    public let coverageRefs: [String]
    public let evidence: String?
    public let freshness: String?
    public let controls: [Control]

    private enum CodingKeys: String, CodingKey {
        case id, jobID, createdAt, title, description, descriptionMd
        case status, source, priority, ref, url
        case domain
        case topicKey = "topic_key"
        case originRef = "origin_ref"
        case revision
        case whyNow = "why_now"
        case sourceURI = "source_uri"
        case coverageRefs = "coverage_refs"
        case evidence, freshness, controls
    }

    public init(
        id: String, jobID: String, createdAt: Date? = nil,
        title: String, descriptionMd: String,
        status: String? = nil, source: String? = nil, priority: String? = nil,
        ref: String? = nil, url: String? = nil, domain: String? = nil,
        topicKey: String? = nil, originRef: String? = nil, revision: String? = nil,
        whyNow: String? = nil, sourceURI: String? = nil, coverageRefs: [String] = [],
        evidence: String? = nil, freshness: String? = nil,
        controls: [Control]
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
        self.domain = domain
        self.topicKey = topicKey
        self.originRef = originRef
        self.revision = revision
        self.whyNow = whyNow
        self.sourceURI = sourceURI
        self.coverageRefs = coverageRefs
        self.evidence = evidence
        self.freshness = freshness
        self.controls = controls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        jobID = try container.decode(String.self, forKey: .jobID)
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
        source = try container.decodeIfPresent(String.self, forKey: .source)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        ref = try container.decodeIfPresent(String.self, forKey: .ref)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        topicKey = try container.decodeIfPresent(String.self, forKey: .topicKey)
        originRef = try container.decodeIfPresent(String.self, forKey: .originRef)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        whyNow = try container.decodeIfPresent(String.self, forKey: .whyNow)
        sourceURI = try container.decodeIfPresent(String.self, forKey: .sourceURI)
        coverageRefs = try container.decodeIfPresent([String].self, forKey: .coverageRefs) ?? []
        evidence = try container.decodeIfPresent(String.self, forKey: .evidence)
        freshness = try container.decodeIfPresent(String.self, forKey: .freshness)
        controls = try container.decode([Control].self, forKey: .controls)
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
        try container.encodeIfPresent(domain, forKey: .domain)
        try container.encodeIfPresent(topicKey, forKey: .topicKey)
        try container.encodeIfPresent(originRef, forKey: .originRef)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(whyNow, forKey: .whyNow)
        try container.encodeIfPresent(sourceURI, forKey: .sourceURI)
        if !coverageRefs.isEmpty { try container.encode(coverageRefs, forKey: .coverageRefs) }
        try container.encodeIfPresent(evidence, forKey: .evidence)
        try container.encodeIfPresent(freshness, forKey: .freshness)
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
