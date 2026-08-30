import Foundation

public enum TeamAuditPayloadTeamAuditSection: String, Codable, Sendable {
    case overview, findings, caseTimelines, individualMetrics, feedbackLineage, agentRepeatMetrics, importObservations, artifacts
}

public enum TeamAuditPayloadAuditMode: String, Codable, Sendable { case baseline, incremental }
public enum TeamAuditPayloadAuditAxis: String, Codable, Sendable { case workflowConformance, workflowFitness, outcomeIntegrity, taskEffectiveness }
public enum TeamAuditPayloadFindingPriority: String, Codable, Sendable { case p0, p1, p2, info }
public enum TeamAuditPayloadFindingState: String, Codable, Sendable { case open, acknowledged, approvedForRemediation, resolved, regressed, superseded }
public enum TeamAuditPayloadRemediationOwner: String, Codable, Sendable { case projectDevTeam, separateExecutionAgent }
public enum TeamAuditPayloadArtifactKind: String, Codable, Sendable { case genericWorkflow, teamRelationship, findingEventChain, fullReport }
public enum TeamAuditPayloadActorRole: String, Codable, Sendable { case plannerLead, teamLead, fullstackEngineer, aiReviewer, prManager }
public enum TeamAuditPayloadRepeatTriggerCause: String, Codable, Sendable {
    case planningFinding,
         reviewFinding,
         ciCodeFailure,
         ciInfrastructureFailure,
         shaOrMetadataMismatch,
         permissionOrCredential,
         hardwareOrEnvironment,
         ownerDecision,
         workflowConfiguration,
         unknown
}
public enum TeamAuditPayloadTaskEffectivenessState: String, Codable, Sendable {
    case effective,
         ineffective,
         regressed,
         pendingDelivery,
         pendingRelease,
         pendingObservation,
         insufficientEvidence
}

public struct TeamAuditPayloadAuditScope: Codable, Sendable {
    public let owner: String
    public let projectID: String?
    public let repository: String?
    public init(owner: String, projectID: String? = nil, repository: String? = nil) {
        self.owner = owner; self.projectID = projectID; self.repository = repository
    }
}

public struct TeamAuditPayloadAuditCursor: Codable, Sendable {
    public let sourceID: String; public let cursorID: String; public let timestamp: Date; public let overlapHours: Int
    public init(sourceID: String, cursorID: String, timestamp: Date, overlapHours: Int) {
        self.sourceID = sourceID; self.cursorID = cursorID; self.timestamp = timestamp; self.overlapHours = overlapHours
    }
}

public struct TeamAuditPayloadInstructionVersion: Codable, Sendable {
    public let sourceID: String; public let updatedAt: Date; public let sha256: String
    public init(sourceID: String, updatedAt: Date, sha256: String) {
        self.sourceID = sourceID; self.updatedAt = updatedAt; self.sha256 = sha256
    }
}

public struct TeamAuditPayloadCoreAxisSummary: Codable, Sendable {
    public let axis: TeamAuditPayloadAuditAxis
    public let totalCases: Int
    public let positive: Int
    public let negative: Int
    public let insufficientEvidence: Int

    public init(
        axis: TeamAuditPayloadAuditAxis,
        totalCases: Int,
        positive: Int,
        negative: Int,
        insufficientEvidence: Int
    ) {
        self.axis = axis
        self.totalCases = totalCases
        self.positive = positive
        self.negative = negative
        self.insufficientEvidence = insufficientEvidence
    }
}

public struct TeamAuditPayloadTaskEffectivenessSummary: Codable, Sendable {
    public let totalEvaluated: Int
    public let effective: Int
    public let ineffective: Int
    public let regressed: Int
    public let pending: Int
    public let insufficientEvidence: Int

    public init(
        totalEvaluated: Int,
        effective: Int,
        ineffective: Int,
        regressed: Int,
        pending: Int,
        insufficientEvidence: Int
    ) {
        self.totalEvaluated = totalEvaluated
        self.effective = effective
        self.ineffective = ineffective
        self.regressed = regressed
        self.pending = pending
        self.insufficientEvidence = insufficientEvidence
    }
}

public struct TeamAuditPayloadPublicationCoverage: Codable, Sendable {
    public let requiredGenericWorkflowCount: Int
    public let publishedGenericWorkflowCount: Int
    public let requiredTeamRelationshipCount: Int
    public let publishedTeamRelationshipCount: Int
    public let requiredP0P1FindingCount: Int
    public let publishedP0P1FindingCount: Int
    public let requiredP0P1ChainCount: Int
    public let publishedP0P1ChainCount: Int
    public let omittedOptionalEntityCount: Int
    public let externalizedEntityCount: Int
    public let fullReport: TeamAuditPayloadFullReportReference?

    public init(
        requiredGenericWorkflowCount: Int,
        publishedGenericWorkflowCount: Int,
        requiredTeamRelationshipCount: Int,
        publishedTeamRelationshipCount: Int,
        requiredP0P1FindingCount: Int,
        publishedP0P1FindingCount: Int,
        requiredP0P1ChainCount: Int,
        publishedP0P1ChainCount: Int,
        omittedOptionalEntityCount: Int,
        externalizedEntityCount: Int,
        fullReport: TeamAuditPayloadFullReportReference? = nil
    ) {
        self.requiredGenericWorkflowCount = requiredGenericWorkflowCount
        self.publishedGenericWorkflowCount = publishedGenericWorkflowCount
        self.requiredTeamRelationshipCount = requiredTeamRelationshipCount
        self.publishedTeamRelationshipCount = publishedTeamRelationshipCount
        self.requiredP0P1FindingCount = requiredP0P1FindingCount
        self.publishedP0P1FindingCount = publishedP0P1FindingCount
        self.requiredP0P1ChainCount = requiredP0P1ChainCount
        self.publishedP0P1ChainCount = publishedP0P1ChainCount
        self.omittedOptionalEntityCount = omittedOptionalEntityCount
        self.externalizedEntityCount = externalizedEntityCount
        self.fullReport = fullReport
    }
}

public struct TeamAuditPayloadFullReportReference: Codable, Sendable {
    public let artifactID: String
    public let title: String
    public let contentSHA256: String
    public let url: String?

    public init(artifactID: String, title: String, contentSHA256: String, url: String? = nil) {
        self.artifactID = artifactID
        self.title = title
        self.contentSHA256 = contentSHA256
        self.url = url
    }
}

public struct TeamAuditPayloadDetailedOverview: Codable, Sendable {
    public let cohort: String?
    public let cursors: [TeamAuditPayloadAuditCursor]
    public let instructionVersions: [TeamAuditPayloadInstructionVersion]
    public let axisSummaries: [TeamAuditPayloadCoreAxisSummary]
    public let taskEffectiveness: TeamAuditPayloadTaskEffectivenessSummary
    public let publicationCoverage: TeamAuditPayloadPublicationCoverage?
    public let collisionCount: Int?
    public let limitations: [String]

    public init(
        cohort: String? = nil,
        cursors: [TeamAuditPayloadAuditCursor] = [],
        instructionVersions: [TeamAuditPayloadInstructionVersion] = [],
        axisSummaries: [TeamAuditPayloadCoreAxisSummary] = [],
        taskEffectiveness: TeamAuditPayloadTaskEffectivenessSummary,
        publicationCoverage: TeamAuditPayloadPublicationCoverage? = nil,
        collisionCount: Int? = nil,
        limitations: [String] = []
    ) {
        self.cohort = cohort
        self.cursors = cursors
        self.instructionVersions = instructionVersions
        self.axisSummaries = axisSummaries
        self.taskEffectiveness = taskEffectiveness
        self.publicationCoverage = publicationCoverage
        self.collisionCount = collisionCount
        self.limitations = limitations
    }
}

public struct TeamAuditPayloadAuditFinding: Codable, Sendable {
    public let fingerprint: String; public let subjectID: String; public let responsibilityLayer: String; public let axis: TeamAuditPayloadAuditAxis; public let priority: TeamAuditPayloadFindingPriority; public let verdict: String; public let state: TeamAuditPayloadFindingState; public let summary: String; public let caseIDs: [String]; public let eventIDs: [String]; public let evidenceRefs: [String]; public let remediationOwner: TeamAuditPayloadRemediationOwner
    public init(fingerprint: String, subjectID: String, responsibilityLayer: String, axis: TeamAuditPayloadAuditAxis, priority: TeamAuditPayloadFindingPriority, verdict: String, state: TeamAuditPayloadFindingState, summary: String, caseIDs: [String] = [], eventIDs: [String] = [], evidenceRefs: [String] = [], remediationOwner: TeamAuditPayloadRemediationOwner = .projectDevTeam) {
        self.fingerprint = fingerprint; self.subjectID = subjectID; self.responsibilityLayer = responsibilityLayer; self.axis = axis; self.priority = priority; self.verdict = verdict; self.state = state; self.summary = summary; self.caseIDs = caseIDs; self.eventIDs = eventIDs; self.evidenceRefs = evidenceRefs; self.remediationOwner = remediationOwner
    }
}

public struct TeamAuditPayloadAuditCase: Codable, Sendable {
    public let caseID: String; public let eventIDs: [String]; public let attemptIDs: [String]; public let limitations: [String]
    public init(caseID: String, eventIDs: [String] = [], attemptIDs: [String] = [], limitations: [String] = []) {
        self.caseID = caseID; self.eventIDs = eventIDs; self.attemptIDs = attemptIDs; self.limitations = limitations
    }
}

public struct TeamAuditPayloadAuditEvent: Codable, Sendable {
    public let eventID: String; public let source: String; public let subjectID: String; public let kind: String; public let revisionSHA: String; public let actorRole: TeamAuditPayloadActorRole; public let timestamp: Date; public let evidenceRef: String?
    public init(eventID: String, source: String, subjectID: String, kind: String, revisionSHA: String, actorRole: TeamAuditPayloadActorRole, timestamp: Date, evidenceRef: String? = nil) {
        self.eventID = eventID; self.source = source; self.subjectID = subjectID; self.kind = kind; self.revisionSHA = revisionSHA; self.actorRole = actorRole; self.timestamp = timestamp; self.evidenceRef = evidenceRef
    }
}

public struct TeamAuditPayloadAuditAttempt: Codable, Sendable {
    public let attemptID: String; public let actorRole: TeamAuditPayloadActorRole; public let triggerCause: String; public let outcome: String; public let evidenceRefs: [String]
    public init(attemptID: String, actorRole: TeamAuditPayloadActorRole, triggerCause: String, outcome: String, evidenceRefs: [String] = []) {
        self.attemptID = attemptID; self.actorRole = actorRole; self.triggerCause = triggerCause; self.outcome = outcome; self.evidenceRefs = evidenceRefs
    }
}

public struct TeamAuditPayloadIndividualMetric: Codable, Sendable {
    public let metricID: String; public let metricDefinition: String; public let observationWindow: String; public let numerator: Double; public let denominator: Double?; public let limitation: String?
    public init(metricID: String, metricDefinition: String, numerator: Double, denominator: Double? = nil, observationWindow: String, limitation: String? = nil) {
        self.metricID = metricID; self.metricDefinition = metricDefinition; self.numerator = numerator; self.denominator = denominator; self.observationWindow = observationWindow; self.limitation = limitation
    }
}

public struct TeamAuditPayloadFeedbackLineage: Codable, Sendable {
    public let lineageID: String; public let problemFingerprint: String; public let originIssueID: String; public let deliveryIssueID: String; public let prURL: String?; public let mergeSHA: String?; public let releaseChannel: String?; public let firstVersion: String?; public let firstBuild: String?; public let availableAt: Date?; public let observationEventIDs: [String]; public let relatedFeedbackIssueIDs: [String]; public let taskEffectiveness: TeamAuditPayloadTaskEffectivenessState
    public init(lineageID: String, problemFingerprint: String, originIssueID: String, deliveryIssueID: String, prURL: String? = nil, mergeSHA: String? = nil, releaseChannel: String? = nil, firstVersion: String? = nil, firstBuild: String? = nil, availableAt: Date? = nil, observationEventIDs: [String] = [], relatedFeedbackIssueIDs: [String] = [], taskEffectiveness: TeamAuditPayloadTaskEffectivenessState = .pendingDelivery) {
        self.lineageID = lineageID; self.problemFingerprint = problemFingerprint; self.originIssueID = originIssueID; self.deliveryIssueID = deliveryIssueID; self.prURL = prURL; self.mergeSHA = mergeSHA; self.releaseChannel = releaseChannel; self.firstVersion = firstVersion; self.firstBuild = firstBuild; self.availableAt = availableAt; self.observationEventIDs = observationEventIDs; self.relatedFeedbackIssueIDs = relatedFeedbackIssueIDs; self.taskEffectiveness = taskEffectiveness
    }
}

public struct TeamAuditPayloadAgentRepeatMetric: Codable, Sendable {
    public let actorRole: TeamAuditPayloadActorRole; public let attemptsTotal: Int; public let repeatCycles: Int; public let repeatCases: Int; public let sameArtifactRepeatCycles: Int; public let changedArtifactRepeatCycles: Int; public let maxCyclesPerCase: Int; public let byCycleKind: [String: Int]; public let byTriggerCause: [TeamAuditPayloadRepeatTriggerCause: Int]; public let subjectIDs: [String]; public let eventIDs: [String]
    public init(actorRole: TeamAuditPayloadActorRole, attemptsTotal: Int, repeatCycles: Int, repeatCases: Int, sameArtifactRepeatCycles: Int, changedArtifactRepeatCycles: Int, maxCyclesPerCase: Int, byCycleKind: [String: Int], byTriggerCause: [TeamAuditPayloadRepeatTriggerCause: Int], subjectIDs: [String] = [], eventIDs: [String] = []) {
        self.actorRole = actorRole; self.attemptsTotal = attemptsTotal; self.repeatCycles = repeatCycles; self.repeatCases = repeatCases; self.sameArtifactRepeatCycles = sameArtifactRepeatCycles; self.changedArtifactRepeatCycles = changedArtifactRepeatCycles; self.maxCyclesPerCase = maxCyclesPerCase; self.byCycleKind = byCycleKind; self.byTriggerCause = byTriggerCause; self.subjectIDs = subjectIDs; self.eventIDs = eventIDs
    }
}

public struct TeamAuditImportCollisionObservation: Codable, Sendable {
    public let observationID: String
    public let parentSnapshotID: String
    public let parentSnapshotSHA256: String
    public let observedAt: Date
    public let source: String
    public let entityKind: String
    public let stableIdentity: String
    public let acceptedSHA256: String
    public let rejectedSHA256: String
    public let disposition: String
    public let limitation: String

    public init(
        observationID: String,
        parentSnapshotID: String,
        parentSnapshotSHA256: String,
        observedAt: Date,
        source: String,
        entityKind: String,
        stableIdentity: String,
        acceptedSHA256: String,
        rejectedSHA256: String,
        disposition: String = "rejectedIdentityHashCollision",
        limitation: String
    ) {
        self.observationID = observationID
        self.parentSnapshotID = parentSnapshotID
        self.parentSnapshotSHA256 = parentSnapshotSHA256
        self.observedAt = observedAt
        self.source = source
        self.entityKind = entityKind
        self.stableIdentity = stableIdentity
        self.acceptedSHA256 = acceptedSHA256
        self.rejectedSHA256 = rejectedSHA256
        self.disposition = disposition
        self.limitation = limitation
    }
}

public struct TeamAuditPayloadArtifactManifestEntry: Codable, Sendable {
    public let artifactID: String; public let snapshotID: String; public let kind: TeamAuditPayloadArtifactKind; public let title: String; public let findingFingerprint: String?; public let caseID: String?; public let eventIDs: [String]; public let revisionEvidence: [String]; public let contentSHA256: String; public let url: String?
    public init(artifactID: String, snapshotID: String, kind: TeamAuditPayloadArtifactKind, title: String, findingFingerprint: String? = nil, caseID: String? = nil, eventIDs: [String] = [], revisionEvidence: [String] = [], contentSHA256: String, url: String? = nil) {
        self.artifactID = artifactID; self.snapshotID = snapshotID; self.kind = kind; self.title = title; self.findingFingerprint = findingFingerprint; self.caseID = caseID; self.eventIDs = eventIDs; self.revisionEvidence = revisionEvidence; self.contentSHA256 = contentSHA256; self.url = url
    }
}

public struct TeamAuditPayload: CardPayloadProtocol, Codable, Sendable {
    public typealias TeamAuditSection = TeamAuditPayloadTeamAuditSection
    public typealias AuditMode = TeamAuditPayloadAuditMode
    public typealias AuditAxis = TeamAuditPayloadAuditAxis
    public typealias FindingPriority = TeamAuditPayloadFindingPriority
    public typealias FindingState = TeamAuditPayloadFindingState
    public typealias RemediationOwner = TeamAuditPayloadRemediationOwner
    public typealias ArtifactKind = TeamAuditPayloadArtifactKind
    public typealias ActorRole = TeamAuditPayloadActorRole
    public typealias RepeatTriggerCause = TeamAuditPayloadRepeatTriggerCause
    public typealias TaskEffectivenessState = TeamAuditPayloadTaskEffectivenessState
    public typealias AuditScope = TeamAuditPayloadAuditScope
    public typealias AuditCursor = TeamAuditPayloadAuditCursor
    public typealias InstructionVersion = TeamAuditPayloadInstructionVersion
    public typealias CoreAxisSummary = TeamAuditPayloadCoreAxisSummary
    public typealias TaskEffectivenessSummary = TeamAuditPayloadTaskEffectivenessSummary
    public typealias PublicationCoverage = TeamAuditPayloadPublicationCoverage
    public typealias FullReportReference = TeamAuditPayloadFullReportReference
    public typealias DetailedOverview = TeamAuditPayloadDetailedOverview
    public typealias AuditFinding = TeamAuditPayloadAuditFinding
    public typealias AuditCase = TeamAuditPayloadAuditCase
    public typealias AuditEvent = TeamAuditPayloadAuditEvent
    public typealias AuditAttempt = TeamAuditPayloadAuditAttempt
    public typealias IndividualMetric = TeamAuditPayloadIndividualMetric
    public typealias FeedbackLineage = TeamAuditPayloadFeedbackLineage
    public typealias AgentRepeatMetric = TeamAuditPayloadAgentRepeatMetric
    public typealias ImportCollisionObservation = TeamAuditImportCollisionObservation
    public typealias ArtifactManifestEntry = TeamAuditPayloadArtifactManifestEntry

    public let snapshotID: String
    public let capturedAt: Date
    public let scope: AuditScope
    public let mode: AuditMode
    public let section: TeamAuditSection
    public let partIndex: Int
    public let partCount: Int
    public let contentSHA256: String
    public let artifactSidecarID: String
    public let artifactSidecarSHA256: String
    public let overview: DetailedOverview?
    public let findings: [AuditFinding]
    public let caseTimelines: [AuditCase]
    public let individualMetrics: [IndividualMetric]
    public let feedbackLineage: [FeedbackLineage]
    public let agentRepeatMetrics: [AgentRepeatMetric]
    public let importObservations: [ImportCollisionObservation]
    public let artifacts: [ArtifactManifestEntry]

    public init(
        snapshotID: String,
        capturedAt: Date,
        scope: AuditScope,
        mode: AuditMode,
        section: TeamAuditSection,
        partIndex: Int,
        partCount: Int,
        contentSHA256: String,
        artifactSidecarID: String,
        artifactSidecarSHA256: String,
        overview: DetailedOverview? = nil,
        findings: [AuditFinding] = [],
        caseTimelines: [AuditCase] = [],
        individualMetrics: [IndividualMetric] = [],
        feedbackLineage: [FeedbackLineage] = [],
        agentRepeatMetrics: [AgentRepeatMetric] = [],
        importObservations: [ImportCollisionObservation] = [],
        artifacts: [ArtifactManifestEntry] = []
    ) {
        self.snapshotID = snapshotID
        self.capturedAt = capturedAt
        self.scope = scope
        self.mode = mode
        self.section = section
        self.partIndex = partIndex
        self.partCount = partCount
        self.contentSHA256 = contentSHA256
        self.artifactSidecarID = artifactSidecarID
        self.artifactSidecarSHA256 = artifactSidecarSHA256
        self.overview = overview
        self.findings = findings
        self.caseTimelines = caseTimelines
        self.individualMetrics = individualMetrics
        self.feedbackLineage = feedbackLineage
        self.agentRepeatMetrics = agentRepeatMetrics
        self.importObservations = importObservations
        self.artifacts = artifacts
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID,
             capturedAt,
             scope,
             mode,
             section,
             partIndex,
             partCount,
             contentSHA256,
             artifactSidecarID,
             artifactSidecarSHA256,
             overview,
             findings,
             caseTimelines,
             individualMetrics,
             feedbackLineage,
             agentRepeatMetrics,
             importObservations,
             artifacts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapshotID = try c.decode(String.self, forKey: .snapshotID)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        scope = try c.decode(AuditScope.self, forKey: .scope)
        mode = try c.decode(AuditMode.self, forKey: .mode)
        section = try c.decode(TeamAuditSection.self, forKey: .section)
        partIndex = try c.decode(Int.self, forKey: .partIndex)
        partCount = try c.decode(Int.self, forKey: .partCount)
        contentSHA256 = try c.decode(String.self, forKey: .contentSHA256)
        artifactSidecarID = try c.decode(String.self, forKey: .artifactSidecarID)
        artifactSidecarSHA256 = try c.decode(String.self, forKey: .artifactSidecarSHA256)
        overview = try c.decodeIfPresent(DetailedOverview.self, forKey: .overview)
        findings = try c.decodeIfPresent([AuditFinding].self, forKey: .findings) ?? []
        caseTimelines = try c.decodeIfPresent([AuditCase].self, forKey: .caseTimelines) ?? []
        individualMetrics = try c.decodeIfPresent([IndividualMetric].self, forKey: .individualMetrics) ?? []
        feedbackLineage = try c.decodeIfPresent([FeedbackLineage].self, forKey: .feedbackLineage) ?? []
        agentRepeatMetrics = try c.decodeIfPresent([AgentRepeatMetric].self, forKey: .agentRepeatMetrics) ?? []
        importObservations = try c.decodeIfPresent([ImportCollisionObservation].self, forKey: .importObservations) ?? []
        artifacts = try c.decodeIfPresent([ArtifactManifestEntry].self, forKey: .artifacts) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(snapshotID, forKey: .snapshotID)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(scope, forKey: .scope)
        try c.encode(mode, forKey: .mode)
        try c.encode(section, forKey: .section)
        try c.encode(partIndex, forKey: .partIndex)
        try c.encode(partCount, forKey: .partCount)
        try c.encode(contentSHA256, forKey: .contentSHA256)
        try c.encode(artifactSidecarID, forKey: .artifactSidecarID)
        try c.encode(artifactSidecarSHA256, forKey: .artifactSidecarSHA256)
        try c.encodeIfPresent(overview, forKey: .overview)
        if !findings.isEmpty { try c.encode(findings, forKey: .findings) }
        if !caseTimelines.isEmpty { try c.encode(caseTimelines, forKey: .caseTimelines) }
        if !individualMetrics.isEmpty { try c.encode(individualMetrics, forKey: .individualMetrics) }
        if !feedbackLineage.isEmpty { try c.encode(feedbackLineage, forKey: .feedbackLineage) }
        if !agentRepeatMetrics.isEmpty { try c.encode(agentRepeatMetrics, forKey: .agentRepeatMetrics) }
        if !importObservations.isEmpty { try c.encode(importObservations, forKey: .importObservations) }
        if !artifacts.isEmpty { try c.encode(artifacts, forKey: .artifacts) }
    }

    public func validateInvariants() throws {
        try validateCoreFields()
        try validateSectionShape()
        try validateSectionCollection()
    }

    private func validateCoreFields() throws {
        try Self.requireNonEmpty(snapshotID, field: "snapshotID")
        try Self.requireNonEmpty(contentSHA256, field: "contentSHA256")
        try Self.requireNonEmpty(artifactSidecarID, field: "artifactSidecarID")
        try Self.requireNonEmpty(artifactSidecarSHA256, field: "artifactSidecarSHA256")
        try Self.requireNonEmpty(scope.owner, field: "scope.owner")
        guard partCount > 0 else { throw Self.invalid("partCount must be positive", field: "partCount") }
        guard partIndex >= 0 else { throw Self.invalid("partIndex must be non-negative", field: "partIndex") }
        guard partIndex < partCount else { throw Self.invalid("partIndex must be less than partCount", field: "partIndex") }
    }

    private func validateSectionShape() throws {
        let counts = [("overview", overview != nil), ("findings", !findings.isEmpty), ("caseTimelines", !caseTimelines.isEmpty), ("individualMetrics", !individualMetrics.isEmpty), ("feedbackLineage", !feedbackLineage.isEmpty), ("agentRepeatMetrics", !agentRepeatMetrics.isEmpty), ("importObservations", !importObservations.isEmpty), ("artifacts", !artifacts.isEmpty)]
        let populated = counts.filter { $0.1 }
        guard populated.count == 1 else { throw Self.invalid("exactly one section collection must be populated", field: "section") }
        guard populated[0].0 == section.rawValue else { throw Self.invalid("section does not match populated collection", field: "section") }
    }

    private func validateSectionCollection() throws {
        switch section {
        case .overview: guard overview != nil else { throw Self.invalid("overview section requires overview", field: "overview") }
        case .findings: try findings.forEach(Self.validateFinding)
        case .caseTimelines: try caseTimelines.forEach(Self.validateCase)
        case .individualMetrics: try individualMetrics.forEach(Self.validateMetric)
        case .feedbackLineage: try feedbackLineage.forEach(Self.validateLineage)
        case .agentRepeatMetrics: try agentRepeatMetrics.forEach(Self.validateRepeatMetric)
        case .importObservations: try importObservations.forEach(Self.validateImportObservation)
        case .artifacts: try artifacts.forEach(Self.validateArtifact)
        }
    }

    private static func validateFinding(_ finding: AuditFinding) throws {
        try requireNonEmpty(finding.fingerprint, field: "findings.fingerprint")
        try requireNonEmpty(finding.subjectID, field: "findings.subjectID")
        try requireNonEmpty(finding.responsibilityLayer, field: "findings.responsibilityLayer")
        try requireNonEmpty(finding.summary, field: "findings.summary")
    }

    private static func validateCase(_ entry: AuditCase) throws {
        try requireNonEmpty(entry.caseID, field: "caseTimelines.caseID")
    }

    private static func validateMetric(_ metric: IndividualMetric) throws {
        try requireNonEmpty(metric.metricID, field: "individualMetrics.metricID")
        try requireNonEmpty(metric.metricDefinition, field: "individualMetrics.metricDefinition")
    }

    private static func validateLineage(_ lineage: FeedbackLineage) throws {
        try requireNonEmpty(lineage.lineageID, field: "feedbackLineage.lineageID")
        try requireNonEmpty(lineage.problemFingerprint, field: "feedbackLineage.problemFingerprint")
    }

    private static func validateRepeatMetric(_ metric: AgentRepeatMetric) throws {
        guard metric.attemptsTotal >= 0 else { throw invalid("attemptsTotal invalid", field: "agentRepeatMetrics.attemptsTotal") }
    }

    private static func validateImportObservation(_ obs: ImportCollisionObservation) throws {
        try requireNonEmpty(obs.observationID, field: "importObservations.observationID")
        try requireNonEmpty(obs.parentSnapshotID, field: "importObservations.parentSnapshotID")
    }

    private static func validateArtifact(_ artifact: ArtifactManifestEntry) throws {
        try requireNonEmpty(artifact.artifactID, field: "artifacts.artifactID")
        try requireNonEmpty(artifact.contentSHA256, field: "artifacts.contentSHA256")
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw invalid("missing required field value", field: field) }
    }

    private static func invalid(_ message: String, field: String) -> XPCError {
        XPCError(code: "schema.payload_decode_failed", message: message, field: field)
    }
}
