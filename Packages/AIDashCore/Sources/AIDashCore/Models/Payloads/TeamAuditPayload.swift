import Foundation
import CryptoKit

public enum TeamAuditSection: String, Codable, Sendable, CaseIterable {
    case overview, findings, caseTimelines, individualMetrics, feedbackLineage, agentRepeatMetrics, importObservations, artifacts
}

public enum AuditMode: String, Codable, Sendable, CaseIterable {
    case baseline, incremental
}

public enum CoreAuditAxis: String, Codable, Sendable, CaseIterable {
    case workflowConformance, workflowFitness, outcomeIntegrity
}

public enum FindingAxis: String, Codable, Sendable, CaseIterable {
    case workflowConformance, workflowFitness, outcomeIntegrity, taskEffectiveness
}

public enum ConformanceVerdict: String, Codable, Sendable, CaseIterable {
    case conformant, nonconformant, insufficientEvidence
}

public enum FitnessVerdict: String, Codable, Sendable, CaseIterable {
    case fit, unfit, insufficientEvidence
}

public enum OutcomeVerdict: String, Codable, Sendable, CaseIterable {
    case intact, compromised, insufficientEvidence
}

public enum CoreAxisVerdict: Sendable, Equatable {
    case workflowConformance(ConformanceVerdict)
    case workflowFitness(FitnessVerdict)
    case outcomeIntegrity(OutcomeVerdict)

    public var rawValue: String {
        switch self {
        case .workflowConformance(let v): return v.rawValue
        case .workflowFitness(let v): return v.rawValue
        case .outcomeIntegrity(let v): return v.rawValue
        }
    }
}

public enum FindingPriority: String, Codable, Sendable, CaseIterable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case info = "info"
}

public enum FindingState: String, Codable, Sendable, CaseIterable {
    case open, acknowledged, approvedForRemediation, resolved, regressed, superseded
}

public enum RemediationOwner: String, Codable, Sendable, CaseIterable {
    case projectDevTeam, separateExecutionAgent
}

public enum ArtifactKind: String, Codable, Sendable, CaseIterable {
    case genericWorkflow, teamRelationship, findingEventChain, fullReport
}

public enum ArtifactRequirement: String, Codable, Sendable, CaseIterable {
    case mandatory, optional
}

public enum ActorRole: String, Codable, Sendable, CaseIterable {
    case plannerLead, teamLead, fullstackEngineer, aiReviewer, prManager
}

public enum ReleaseChannel: String, Codable, Sendable, CaseIterable {
    case testflight, appStore, production, `internal`
}

public enum ImportObservationDisposition: String, Codable, Sendable, CaseIterable {
    case rejectedIdentityHashCollision
}

public enum RepeatTriggerCause: String, Codable, Sendable, CaseIterable {
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

public enum TaskEffectivenessState: String, Codable, Sendable, CaseIterable {
    case effective,
         ineffective,
         regressed,
         pendingDelivery,
         pendingRelease,
         pendingObservation,
         insufficientEvidence
}

public enum ExternalizableEntityKind: String, Codable, Sendable, CaseIterable {
    case p2Finding,
         infoFinding,
         caseTimeline,
         individualMetric,
         feedbackLineage,
         agentRepeatMetric,
         importObservation,
         optionalArtifact
}

public struct AuditScope: Codable, Sendable, Equatable {
    public let owner: String
    public let projectID: String?
    public let repository: String?

    public init(owner: String, projectID: String? = nil, repository: String? = nil) {
        self.owner = owner
        self.projectID = projectID
        self.repository = repository
    }
}

public struct AuditCohort: Codable, Sendable, Equatable {
    public let cohortID: String
    public let caseIDs: [String]

    public init(cohortID: String, caseIDs: [String] = []) {
        self.cohortID = cohortID
        self.caseIDs = caseIDs
    }
}

public struct AuditCursor: Codable, Sendable, Equatable {
    public let sourceID: String
    public let cursorID: String
    public let timestamp: Date
    public let overlapHours: Int

    public init(sourceID: String, cursorID: String, timestamp: Date, overlapHours: Int = 0) {
        self.sourceID = sourceID
        self.cursorID = cursorID
        self.timestamp = timestamp
        self.overlapHours = overlapHours
    }
}

public struct InstructionVersion: Codable, Sendable, Equatable {
    public let sourceID: String
    public let updatedAt: Date
    public let sha256: String

    public init(sourceID: String, updatedAt: Date, sha256: String) {
        self.sourceID = sourceID
        self.updatedAt = updatedAt
        self.sha256 = sha256
    }
}

public struct EvidenceCoverage: Codable, Sendable, Equatable {
    public let requiredEvidenceCount: Int
    public let availableEvidenceCount: Int
    public let missingEvidenceCount: Int
    public let redactedEvidenceCount: Int
    public let limitations: [String]

    public init(
        requiredEvidenceCount: Int,
        availableEvidenceCount: Int,
        missingEvidenceCount: Int = 0,
        redactedEvidenceCount: Int = 0,
        limitations: [String] = []
    ) {
        self.requiredEvidenceCount = requiredEvidenceCount
        self.availableEvidenceCount = availableEvidenceCount
        self.missingEvidenceCount = missingEvidenceCount
        self.redactedEvidenceCount = redactedEvidenceCount
        self.limitations = limitations
    }
}

public struct CoreAxisSummary: Codable, Sendable, Equatable {
    public let axis: CoreAuditAxis
    public let verdict: CoreAxisVerdict
    public let totalCases: Int
    public let positive: Int
    public let negative: Int
    public let insufficientEvidence: Int

    public init(
        axis: CoreAuditAxis,
        verdict: CoreAxisVerdict,
        totalCases: Int,
        positive: Int = 0,
        negative: Int = 0,
        insufficientEvidence: Int = 0
    ) {
        self.axis = axis
        self.verdict = verdict
        self.totalCases = totalCases
        self.positive = positive
        self.negative = negative
        self.insufficientEvidence = insufficientEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case axis, verdict, totalCases, positive, negative, insufficientEvidence
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let axis = try c.decode(CoreAuditAxis.self, forKey: .axis)
        let rawVerdict = try c.decode(String.self, forKey: .verdict)
        self.axis = axis
        self.totalCases = try c.decode(Int.self, forKey: .totalCases)
        self.positive = try c.decode(Int.self, forKey: .positive)
        self.negative = try c.decode(Int.self, forKey: .negative)
        self.insufficientEvidence = try c.decode(Int.self, forKey: .insufficientEvidence)

        switch axis {
        case .workflowConformance:
            guard let v = ConformanceVerdict(rawValue: rawVerdict) else {
                throw DecodingError.dataCorruptedError(forKey: .verdict, in: c, debugDescription: "Invalid ConformanceVerdict: \(rawVerdict)")
            }
            self.verdict = .workflowConformance(v)
        case .workflowFitness:
            guard let v = FitnessVerdict(rawValue: rawVerdict) else {
                throw DecodingError.dataCorruptedError(forKey: .verdict, in: c, debugDescription: "Invalid FitnessVerdict: \(rawVerdict)")
            }
            self.verdict = .workflowFitness(v)
        case .outcomeIntegrity:
            guard let v = OutcomeVerdict(rawValue: rawVerdict) else {
                throw DecodingError.dataCorruptedError(forKey: .verdict, in: c, debugDescription: "Invalid OutcomeVerdict: \(rawVerdict)")
            }
            self.verdict = .outcomeIntegrity(v)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(axis, forKey: .axis)
        try c.encode(verdict.rawValue, forKey: .verdict)
        try c.encode(totalCases, forKey: .totalCases)
        try c.encode(positive, forKey: .positive)
        try c.encode(negative, forKey: .negative)
        try c.encode(insufficientEvidence, forKey: .insufficientEvidence)
    }
}

public struct TaskEffectivenessSummary: Codable, Sendable, Equatable {
    public let totalEvaluated: Int
    public let effective: Int
    public let ineffective: Int
    public let regressed: Int
    public let pending: Int
    public let insufficientEvidence: Int

    public init(
        totalEvaluated: Int,
        effective: Int = 0,
        ineffective: Int = 0,
        regressed: Int = 0,
        pending: Int = 0,
        insufficientEvidence: Int = 0
    ) {
        self.totalEvaluated = totalEvaluated
        self.effective = effective
        self.ineffective = ineffective
        self.regressed = regressed
        self.pending = pending
        self.insufficientEvidence = insufficientEvidence
    }
}

public struct FullReportReference: Codable, Sendable, Equatable {
    public let artifactID: String
    public let title: String
    public let contentSHA256: String
    public let url: String?
    public let sidecarID: String
    public let sidecarSHA256: String

    public init(
        artifactID: String,
        title: String,
        contentSHA256: String,
        url: String? = nil,
        sidecarID: String,
        sidecarSHA256: String
    ) {
        self.artifactID = artifactID
        self.title = title
        self.contentSHA256 = contentSHA256
        self.url = url
        self.sidecarID = sidecarID
        self.sidecarSHA256 = sidecarSHA256
    }
}

public struct PublicationCoverage: Codable, Sendable, Equatable {
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
    public let fullReport: FullReportReference?

    public init(
        requiredGenericWorkflowCount: Int = 0,
        publishedGenericWorkflowCount: Int = 0,
        requiredTeamRelationshipCount: Int = 0,
        publishedTeamRelationshipCount: Int = 0,
        requiredP0P1FindingCount: Int = 0,
        publishedP0P1FindingCount: Int = 0,
        requiredP0P1ChainCount: Int = 0,
        publishedP0P1ChainCount: Int = 0,
        omittedOptionalEntityCount: Int = 0,
        externalizedEntityCount: Int = 0,
        fullReport: FullReportReference? = nil
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

public struct DetailedOverview: Codable, Sendable, Equatable {
    public let cohort: AuditCohort?
    public let cursors: [AuditCursor]
    public let instructionVersions: [InstructionVersion]
    public let evidenceCoverage: EvidenceCoverage
    public let axisSummaries: [CoreAxisSummary]
    public let taskEffectiveness: TaskEffectivenessSummary
    public let publicationCoverage: PublicationCoverage?
    public let collisionCount: Int?
    public let limitations: [String]

    public init(
        cohort: AuditCohort? = nil,
        cursors: [AuditCursor] = [],
        instructionVersions: [InstructionVersion] = [],
        evidenceCoverage: EvidenceCoverage,
        axisSummaries: [CoreAxisSummary] = [],
        taskEffectiveness: TaskEffectivenessSummary,
        publicationCoverage: PublicationCoverage? = nil,
        collisionCount: Int? = nil,
        limitations: [String] = []
    ) {
        self.cohort = cohort
        self.cursors = cursors
        self.instructionVersions = instructionVersions
        self.evidenceCoverage = evidenceCoverage
        self.axisSummaries = axisSummaries
        self.taskEffectiveness = taskEffectiveness
        self.publicationCoverage = publicationCoverage
        self.collisionCount = collisionCount
        self.limitations = limitations
    }
}

public struct FindingReference: Codable, Sendable, Equatable {
    public let fingerprint: String
    public let priority: FindingPriority

    public init(fingerprint: String, priority: FindingPriority) {
        self.fingerprint = fingerprint
        self.priority = priority
    }
}

public struct ArtifactReference: Codable, Sendable, Equatable {
    public let artifactID: String
    public let kind: ArtifactKind
    public let contentSHA256: String
    public let url: String?
    public let sidecarID: String
    public let sidecarSHA256: String

    public init(
        artifactID: String,
        kind: ArtifactKind,
        contentSHA256: String,
        url: String? = nil,
        sidecarID: String,
        sidecarSHA256: String
    ) {
        self.artifactID = artifactID
        self.kind = kind
        self.contentSHA256 = contentSHA256
        self.url = url
        self.sidecarID = sidecarID
        self.sidecarSHA256 = sidecarSHA256
    }
}

public struct SnapshotReferenceCatalog: Codable, Sendable, Equatable {
    public let caseIDs: [String]
    public let eventIDs: [String]
    public let evidenceRefs: [String]
    public let subjectIDs: [String]
    public let revisionEvidenceRefs: [String]
    public let findings: [FindingReference]
    public let artifacts: [ArtifactReference]

    public init(
        caseIDs: [String] = [],
        eventIDs: [String] = [],
        evidenceRefs: [String] = [],
        subjectIDs: [String] = [],
        revisionEvidenceRefs: [String] = [],
        findings: [FindingReference] = [],
        artifacts: [ArtifactReference] = []
    ) {
        self.caseIDs = caseIDs
        self.eventIDs = eventIDs
        self.evidenceRefs = evidenceRefs
        self.subjectIDs = subjectIDs
        self.revisionEvidenceRefs = revisionEvidenceRefs
        self.findings = findings
        self.artifacts = artifacts
    }
}

public struct AuditFinding: Codable, Sendable, Equatable {
    public let fingerprint: String
    public let subjectID: String
    public let responsibilityLayer: String
    public let axis: FindingAxis
    public let priority: FindingPriority
    public let verdict: String
    public let state: FindingState
    public let summary: String
    public let caseIDs: [String]
    public let eventIDs: [String]
    public let evidenceRefs: [String]
    public let remediationOwner: RemediationOwner

    public init(
        fingerprint: String,
        subjectID: String,
        responsibilityLayer: String,
        axis: FindingAxis,
        priority: FindingPriority,
        verdict: String,
        state: FindingState,
        summary: String,
        caseIDs: [String] = [],
        eventIDs: [String] = [],
        evidenceRefs: [String] = [],
        remediationOwner: RemediationOwner = .projectDevTeam
    ) {
        self.fingerprint = fingerprint
        self.subjectID = subjectID
        self.responsibilityLayer = responsibilityLayer
        self.axis = axis
        self.priority = priority
        self.verdict = verdict
        self.state = state
        self.summary = summary
        self.caseIDs = caseIDs
        self.eventIDs = eventIDs
        self.evidenceRefs = evidenceRefs
        self.remediationOwner = remediationOwner
    }
}

public struct AuditEvent: Codable, Sendable, Equatable {
    public let eventID: String
    public let caseID: String
    public let source: String
    public let subjectID: String
    public let actorRole: ActorRole
    public let kind: String
    public let timestamp: Date
    public let revisionSHA: String
    public let evidenceRef: String?

    public init(
        eventID: String,
        caseID: String,
        source: String,
        subjectID: String,
        actorRole: ActorRole,
        kind: String,
        timestamp: Date,
        revisionSHA: String,
        evidenceRef: String? = nil
    ) {
        self.eventID = eventID
        self.caseID = caseID
        self.source = source
        self.subjectID = subjectID
        self.actorRole = actorRole
        self.kind = kind
        self.timestamp = timestamp
        self.revisionSHA = revisionSHA
        self.evidenceRef = evidenceRef
    }
}

public struct AuditAttempt: Codable, Sendable, Equatable {
    public let attemptID: String
    public let caseID: String
    public let actorRole: ActorRole
    public let cycle: String
    public let triggerCause: RepeatTriggerCause
    public let outcome: String
    public let evidenceRefs: [String]

    public init(
        attemptID: String,
        caseID: String,
        actorRole: ActorRole,
        cycle: String = "1",
        triggerCause: RepeatTriggerCause = .unknown,
        outcome: String,
        evidenceRefs: [String] = []
    ) {
        self.attemptID = attemptID
        self.caseID = caseID
        self.actorRole = actorRole
        self.cycle = cycle
        self.triggerCause = triggerCause
        self.outcome = outcome
        self.evidenceRefs = evidenceRefs
    }
}

public struct AuditCaseTimeline: Codable, Sendable, Equatable {
    public let caseID: String
    public let eventIDs: [String]
    public let attemptIDs: [String]
    public let events: [AuditEvent]
    public let attempts: [AuditAttempt]
    public let limitations: [String]

    public init(
        caseID: String,
        eventIDs: [String] = [],
        attemptIDs: [String] = [],
        events: [AuditEvent] = [],
        attempts: [AuditAttempt] = [],
        limitations: [String] = []
    ) {
        self.caseID = caseID
        self.eventIDs = eventIDs
        self.attemptIDs = attemptIDs
        self.events = events
        self.attempts = attempts
        self.limitations = limitations
    }
}

public struct IndividualMetric: Codable, Sendable, Equatable {
    public let metricID: String
    public let metricDefinition: String
    public let observationWindow: String
    public let numerator: Double
    public let denominator: Double?
    public let limitation: String?

    public init(
        metricID: String,
        metricDefinition: String,
        numerator: Double,
        denominator: Double? = nil,
        observationWindow: String,
        limitation: String? = nil
    ) {
        self.metricID = metricID
        self.metricDefinition = metricDefinition
        self.numerator = numerator
        self.denominator = denominator
        self.observationWindow = observationWindow
        self.limitation = limitation
    }
}

public struct FeedbackLineage: Codable, Sendable, Equatable {
    public let lineageID: String
    public let problemFingerprint: String
    public let originIssueID: String
    public let deliveryIssueID: String
    public let prURL: String?
    public let mergeSHA: String?
    public let releaseChannel: ReleaseChannel?
    public let firstVersion: String?
    public let firstBuild: String?
    public let availableAt: Date?
    public let observationEventIDs: [String]
    public let relatedFeedbackIssueIDs: [String]
    public let taskEffectiveness: TaskEffectivenessState

    public init(
        lineageID: String,
        problemFingerprint: String,
        originIssueID: String,
        deliveryIssueID: String,
        prURL: String? = nil,
        mergeSHA: String? = nil,
        releaseChannel: ReleaseChannel? = nil,
        firstVersion: String? = nil,
        firstBuild: String? = nil,
        availableAt: Date? = nil,
        observationEventIDs: [String] = [],
        relatedFeedbackIssueIDs: [String] = [],
        taskEffectiveness: TaskEffectivenessState = .pendingDelivery
    ) {
        self.lineageID = lineageID
        self.problemFingerprint = problemFingerprint
        self.originIssueID = originIssueID
        self.deliveryIssueID = deliveryIssueID
        self.prURL = prURL
        self.mergeSHA = mergeSHA
        self.releaseChannel = releaseChannel
        self.firstVersion = firstVersion
        self.firstBuild = firstBuild
        self.availableAt = availableAt
        self.observationEventIDs = observationEventIDs
        self.relatedFeedbackIssueIDs = relatedFeedbackIssueIDs
        self.taskEffectiveness = taskEffectiveness
    }
}

public struct PlannerLeadRepeatMetrics: Codable, Sendable, Equatable {
    public let planningRevisionRounds: Int
    public let planningReviewRepeatCycles: Int
    public let planningSameRevisionReReviews: Int
    public let planningHandoffRepeatCycles: Int

    public init(
        planningRevisionRounds: Int = 0,
        planningReviewRepeatCycles: Int = 0,
        planningSameRevisionReReviews: Int = 0,
        planningHandoffRepeatCycles: Int = 0
    ) {
        self.planningRevisionRounds = planningRevisionRounds
        self.planningReviewRepeatCycles = planningReviewRepeatCycles
        self.planningSameRevisionReReviews = planningSameRevisionReReviews
        self.planningHandoffRepeatCycles = planningHandoffRepeatCycles
    }
}

public struct TeamLeadRepeatMetrics: Codable, Sendable, Equatable {
    public let recoveryDispatchRounds: Int
    public let recoveryDispatchRepeatCycles: Int
    public let sameRecoveryKeyRedispatches: Int
    public let ownerEscalationRepeatCycles: Int

    public init(
        recoveryDispatchRounds: Int = 0,
        recoveryDispatchRepeatCycles: Int = 0,
        sameRecoveryKeyRedispatches: Int = 0,
        ownerEscalationRepeatCycles: Int = 0
    ) {
        self.recoveryDispatchRounds = recoveryDispatchRounds
        self.recoveryDispatchRepeatCycles = recoveryDispatchRepeatCycles
        self.sameRecoveryKeyRedispatches = sameRecoveryKeyRedispatches
        self.ownerEscalationRepeatCycles = ownerEscalationRepeatCycles
    }
}

public struct FullstackEngineerRepeatMetrics: Codable, Sendable, Equatable {
    public let implementationRevisionRounds: Int
    public let reviewFixRounds: Int
    public let ciRepairRounds: Int
    public let sameReviewFindingRepeats: Int
    public let sameCIFailureRepeats: Int
    public let handoffRepairRounds: Int

    public init(
        implementationRevisionRounds: Int = 0,
        reviewFixRounds: Int = 0,
        ciRepairRounds: Int = 0,
        sameReviewFindingRepeats: Int = 0,
        sameCIFailureRepeats: Int = 0,
        handoffRepairRounds: Int = 0
    ) {
        self.implementationRevisionRounds = implementationRevisionRounds
        self.reviewFixRounds = reviewFixRounds
        self.ciRepairRounds = ciRepairRounds
        self.sameReviewFindingRepeats = sameReviewFindingRepeats
        self.sameCIFailureRepeats = sameCIFailureRepeats
        self.handoffRepairRounds = handoffRepairRounds
    }
}

public struct AIReviewerRepeatMetrics: Codable, Sendable, Equatable {
    public let reviewRounds: Int
    public let reviewRepeatCycles: Int
    public let sameSHAReReviews: Int
    public let changedSHAReReviews: Int
    public let inconclusiveReviewRounds: Int
    public let changesRequestedRounds: Int

    public init(
        reviewRounds: Int = 0,
        reviewRepeatCycles: Int = 0,
        sameSHAReReviews: Int = 0,
        changedSHAReReviews: Int = 0,
        inconclusiveReviewRounds: Int = 0,
        changesRequestedRounds: Int = 0
    ) {
        self.reviewRounds = reviewRounds
        self.reviewRepeatCycles = reviewRepeatCycles
        self.sameSHAReReviews = sameSHAReReviews
        self.changedSHAReReviews = changedSHAReReviews
        self.inconclusiveReviewRounds = inconclusiveReviewRounds
        self.changesRequestedRounds = changesRequestedRounds
    }
}

public struct PRManagerRepeatMetrics: Codable, Sendable, Equatable {
    public let ciSupervisionRounds: Int
    public let ciSupervisionRepeatCycles: Int
    public let sameSHACIReruns: Int
    public let shippingAttemptRounds: Int
    public let shippingAttemptRepeatCycles: Int
    public let implementationReturnRounds: Int

    public init(
        ciSupervisionRounds: Int = 0,
        ciSupervisionRepeatCycles: Int = 0,
        sameSHACIReruns: Int = 0,
        shippingAttemptRounds: Int = 0,
        shippingAttemptRepeatCycles: Int = 0,
        implementationReturnRounds: Int = 0
    ) {
        self.ciSupervisionRounds = ciSupervisionRounds
        self.ciSupervisionRepeatCycles = ciSupervisionRepeatCycles
        self.sameSHACIReruns = sameSHACIReruns
        self.shippingAttemptRounds = shippingAttemptRounds
        self.shippingAttemptRepeatCycles = shippingAttemptRepeatCycles
        self.implementationReturnRounds = implementationReturnRounds
    }
}

public enum RoleSpecificRepeatMetrics: Codable, Sendable, Equatable {
    case plannerLead(PlannerLeadRepeatMetrics)
    case teamLead(TeamLeadRepeatMetrics)
    case fullstackEngineer(FullstackEngineerRepeatMetrics)
    case aiReviewer(AIReviewerRepeatMetrics)
    case prManager(PRManagerRepeatMetrics)

    public var role: ActorRole {
        switch self {
        case .plannerLead: return .plannerLead
        case .teamLead: return .teamLead
        case .fullstackEngineer: return .fullstackEngineer
        case .aiReviewer: return .aiReviewer
        case .prManager: return .prManager
        }
    }

    private enum CodingKeys: String, CodingKey {
        case plannerLead, teamLead, fullstackEngineer, aiReviewer, prManager
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.plannerLead) {
            self = .plannerLead(try c.decode(PlannerLeadRepeatMetrics.self, forKey: .plannerLead))
        } else if c.contains(.teamLead) {
            self = .teamLead(try c.decode(TeamLeadRepeatMetrics.self, forKey: .teamLead))
        } else if c.contains(.fullstackEngineer) {
            self = .fullstackEngineer(try c.decode(FullstackEngineerRepeatMetrics.self, forKey: .fullstackEngineer))
        } else if c.contains(.aiReviewer) {
            self = .aiReviewer(try c.decode(AIReviewerRepeatMetrics.self, forKey: .aiReviewer))
        } else if c.contains(.prManager) {
            self = .prManager(try c.decode(PRManagerRepeatMetrics.self, forKey: .prManager))
        } else {
            if let metrics = try? PlannerLeadRepeatMetrics(from: decoder) {
                self = .plannerLead(metrics)
            } else if let metrics = try? TeamLeadRepeatMetrics(from: decoder) {
                self = .teamLead(metrics)
            } else if let metrics = try? FullstackEngineerRepeatMetrics(from: decoder) {
                self = .fullstackEngineer(metrics)
            } else if let metrics = try? AIReviewerRepeatMetrics(from: decoder) {
                self = .aiReviewer(metrics)
            } else if let metrics = try? PRManagerRepeatMetrics(from: decoder) {
                self = .prManager(metrics)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown RoleSpecificRepeatMetrics")
                )
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plannerLead(let m): try c.encode(m, forKey: .plannerLead)
        case .teamLead(let m): try c.encode(m, forKey: .teamLead)
        case .fullstackEngineer(let m): try c.encode(m, forKey: .fullstackEngineer)
        case .aiReviewer(let m): try c.encode(m, forKey: .aiReviewer)
        case .prManager(let m): try c.encode(m, forKey: .prManager)
        }
    }
}

public struct AgentRepeatMetric: Codable, Sendable, Equatable {
    public let actorRole: ActorRole
    public let attemptsTotal: Int
    public let repeatCycles: Int
    public let repeatCases: Int
    public let sameArtifactRepeatCycles: Int
    public let changedArtifactRepeatCycles: Int
    public let maxCyclesPerCase: Int
    public let byCycleKind: [String: Int]
    public let byTriggerCause: [RepeatTriggerCause: Int]
    public let roleSpecific: RoleSpecificRepeatMetrics
    public let subjectIDs: [String]
    public let eventIDs: [String]

    public init(
        actorRole: ActorRole,
        attemptsTotal: Int,
        repeatCycles: Int = 0,
        repeatCases: Int = 0,
        sameArtifactRepeatCycles: Int = 0,
        changedArtifactRepeatCycles: Int = 0,
        maxCyclesPerCase: Int = 0,
        byCycleKind: [String: Int] = [:],
        byTriggerCause: [RepeatTriggerCause: Int] = [:],
        roleSpecific: RoleSpecificRepeatMetrics,
        subjectIDs: [String] = [],
        eventIDs: [String] = []
    ) {
        self.actorRole = actorRole
        self.attemptsTotal = attemptsTotal
        self.repeatCycles = repeatCycles
        self.repeatCases = repeatCases
        self.sameArtifactRepeatCycles = sameArtifactRepeatCycles
        self.changedArtifactRepeatCycles = changedArtifactRepeatCycles
        self.maxCyclesPerCase = maxCyclesPerCase
        self.byCycleKind = byCycleKind
        self.byTriggerCause = byTriggerCause
        self.roleSpecific = roleSpecific
        self.subjectIDs = subjectIDs
        self.eventIDs = eventIDs
    }
}

public struct ImportCollisionObservation: Codable, Sendable, Equatable {
    public let observationID: String
    public let parentSnapshotID: String
    public let parentSnapshotSHA256: String
    public let observedAt: Date
    public let source: String
    public let entityKind: String
    public let stableIdentity: String
    public let acceptedSHA256: String
    public let rejectedSHA256: String
    public let disposition: ImportObservationDisposition
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
        disposition: ImportObservationDisposition = .rejectedIdentityHashCollision,
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

public struct ArtifactManifestEntry: Codable, Sendable, Equatable {
    public let artifactID: String
    public let snapshotID: String
    public let kind: ArtifactKind
    public let title: String
    public let findingFingerprint: String?
    public let caseID: String?
    public let eventIDs: [String]
    public let revisionEvidence: [String]
    public let contentSHA256: String
    public let url: String?
    public let requirement: ArtifactRequirement
    public let sidecarID: String
    public let sidecarSHA256: String

    public init(
        artifactID: String,
        snapshotID: String,
        kind: ArtifactKind,
        title: String,
        findingFingerprint: String? = nil,
        caseID: String? = nil,
        eventIDs: [String] = [],
        revisionEvidence: [String] = [],
        contentSHA256: String,
        url: String? = nil,
        requirement: ArtifactRequirement = .mandatory,
        sidecarID: String,
        sidecarSHA256: String
    ) {
        self.artifactID = artifactID
        self.snapshotID = snapshotID
        self.kind = kind
        self.title = title
        self.findingFingerprint = findingFingerprint
        self.caseID = caseID
        self.eventIDs = eventIDs
        self.revisionEvidence = revisionEvidence
        self.contentSHA256 = contentSHA256
        self.url = url
        self.requirement = requirement
        self.sidecarID = sidecarID
        self.sidecarSHA256 = sidecarSHA256
    }
}

public struct GrillLinks: Codable, Sendable, Equatable {
    public let grillMeURL: String?
    public let grillWithDocsURL: String?
    public let sidecarID: String
    public let sidecarSHA256: String

    public init(
        grillMeURL: String? = nil,
        grillWithDocsURL: String? = nil,
        sidecarID: String,
        sidecarSHA256: String
    ) {
        self.grillMeURL = grillMeURL
        self.grillWithDocsURL = grillWithDocsURL
        self.sidecarID = sidecarID
        self.sidecarSHA256 = sidecarSHA256
    }
}

public struct ExternalizedEntityReference: Codable, Sendable, Equatable {
    public let entityKind: ExternalizableEntityKind
    public let stableID: String
    public let encodedByteCount: Int
    public let reason: String
    public let sidecarID: String
    public let sidecarSHA256: String
    public let fullReport: FullReportReference

    public init(
        entityKind: ExternalizableEntityKind,
        stableID: String,
        encodedByteCount: Int,
        reason: String = "exceedsInlinePayloadLimit",
        sidecarID: String,
        sidecarSHA256: String,
        fullReport: FullReportReference
    ) {
        self.entityKind = entityKind
        self.stableID = stableID
        self.encodedByteCount = encodedByteCount
        self.reason = reason
        self.sidecarID = sidecarID
        self.sidecarSHA256 = sidecarSHA256
        self.fullReport = fullReport
    }
}

public struct ArtifactSection: Codable, Sendable, Equatable {
    public let entries: [ArtifactManifestEntry]
    public let fullReport: FullReportReference?
    public let externalizedEntities: [ExternalizedEntityReference]
    public let grillLinks: GrillLinks?

    public init(
        entries: [ArtifactManifestEntry] = [],
        fullReport: FullReportReference? = nil,
        externalizedEntities: [ExternalizedEntityReference] = [],
        grillLinks: GrillLinks? = nil
    ) {
        self.entries = entries
        self.fullReport = fullReport
        self.externalizedEntities = externalizedEntities
        self.grillLinks = grillLinks
    }
}

public struct TeamAuditPayload: CardPayloadProtocol, Codable, Sendable, Equatable {
    public typealias TeamAuditSection = AIDashCore.TeamAuditSection
    public typealias AuditMode = AIDashCore.AuditMode
    public typealias AuditScope = AIDashCore.AuditScope
    public typealias AuditCohort = AIDashCore.AuditCohort
    public typealias AuditCursor = AIDashCore.AuditCursor
    public typealias InstructionVersion = AIDashCore.InstructionVersion
    public typealias EvidenceCoverage = AIDashCore.EvidenceCoverage
    public typealias CoreAuditAxis = AIDashCore.CoreAuditAxis
    public typealias FindingAxis = AIDashCore.FindingAxis
    public typealias ConformanceVerdict = AIDashCore.ConformanceVerdict
    public typealias FitnessVerdict = AIDashCore.FitnessVerdict
    public typealias OutcomeVerdict = AIDashCore.OutcomeVerdict
    public typealias CoreAxisVerdict = AIDashCore.CoreAxisVerdict
    public typealias CoreAxisSummary = AIDashCore.CoreAxisSummary
    public typealias TaskEffectivenessSummary = AIDashCore.TaskEffectivenessSummary
    public typealias PublicationCoverage = AIDashCore.PublicationCoverage
    public typealias FullReportReference = AIDashCore.FullReportReference
    public typealias SnapshotReferenceCatalog = AIDashCore.SnapshotReferenceCatalog
    public typealias FindingReference = AIDashCore.FindingReference
    public typealias ArtifactReference = AIDashCore.ArtifactReference
    public typealias DetailedOverview = AIDashCore.DetailedOverview
    public typealias AuditFinding = AIDashCore.AuditFinding
    public typealias FindingPriority = AIDashCore.FindingPriority
    public typealias FindingState = AIDashCore.FindingState
    public typealias RemediationOwner = AIDashCore.RemediationOwner
    public typealias AuditCaseTimeline = AIDashCore.AuditCaseTimeline
    public typealias AuditEvent = AIDashCore.AuditEvent
    public typealias AuditAttempt = AIDashCore.AuditAttempt
    public typealias ActorRole = AIDashCore.ActorRole
    public typealias IndividualMetric = AIDashCore.IndividualMetric
    public typealias FeedbackLineage = AIDashCore.FeedbackLineage
    public typealias ReleaseChannel = AIDashCore.ReleaseChannel
    public typealias TaskEffectivenessState = AIDashCore.TaskEffectivenessState
    public typealias AgentRepeatMetric = AIDashCore.AgentRepeatMetric
    public typealias RepeatTriggerCause = AIDashCore.RepeatTriggerCause
    public typealias RoleSpecificRepeatMetrics = AIDashCore.RoleSpecificRepeatMetrics
    public typealias PlannerLeadRepeatMetrics = AIDashCore.PlannerLeadRepeatMetrics
    public typealias TeamLeadRepeatMetrics = AIDashCore.TeamLeadRepeatMetrics
    public typealias FullstackEngineerRepeatMetrics = AIDashCore.FullstackEngineerRepeatMetrics
    public typealias AIReviewerRepeatMetrics = AIDashCore.AIReviewerRepeatMetrics
    public typealias PRManagerRepeatMetrics = AIDashCore.PRManagerRepeatMetrics
    public typealias ImportCollisionObservation = AIDashCore.ImportCollisionObservation
    public typealias ImportObservationDisposition = AIDashCore.ImportObservationDisposition
    public typealias ArtifactManifestEntry = AIDashCore.ArtifactManifestEntry
    public typealias ArtifactSection = AIDashCore.ArtifactSection
    public typealias ArtifactKind = AIDashCore.ArtifactKind
    public typealias ArtifactRequirement = AIDashCore.ArtifactRequirement
    public typealias GrillLinks = AIDashCore.GrillLinks
    public typealias ExternalizedEntityReference = AIDashCore.ExternalizedEntityReference
    public typealias ExternalizableEntityKind = AIDashCore.ExternalizableEntityKind

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
    public let referenceCatalog: SnapshotReferenceCatalog
    public let overview: DetailedOverview?
    public let findings: [AuditFinding]
    public let caseTimelines: [AuditCaseTimeline]
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
        referenceCatalog: SnapshotReferenceCatalog = SnapshotReferenceCatalog(),
        overview: DetailedOverview? = nil,
        findings: [AuditFinding] = [],
        caseTimelines: [AuditCaseTimeline] = [],
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
        self.referenceCatalog = referenceCatalog
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
             referenceCatalog,
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
        referenceCatalog = try c.decodeIfPresent(SnapshotReferenceCatalog.self, forKey: .referenceCatalog) ?? SnapshotReferenceCatalog()
        overview = try c.decodeIfPresent(DetailedOverview.self, forKey: .overview)
        findings = try c.decodeIfPresent([AuditFinding].self, forKey: .findings) ?? []
        caseTimelines = try c.decodeIfPresent([AuditCaseTimeline].self, forKey: .caseTimelines) ?? []
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
        try c.encode(referenceCatalog, forKey: .referenceCatalog)
        try c.encodeIfPresent(overview, forKey: .overview)
        if !findings.isEmpty { try c.encode(findings, forKey: .findings) }
        if !caseTimelines.isEmpty { try c.encode(caseTimelines, forKey: .caseTimelines) }
        if !individualMetrics.isEmpty { try c.encode(individualMetrics, forKey: .individualMetrics) }
        if !feedbackLineage.isEmpty { try c.encode(feedbackLineage, forKey: .feedbackLineage) }
        if !agentRepeatMetrics.isEmpty { try c.encode(agentRepeatMetrics, forKey: .agentRepeatMetrics) }
        if !importObservations.isEmpty { try c.encode(importObservations, forKey: .importObservations) }
        if !artifacts.isEmpty { try c.encode(artifacts, forKey: .artifacts) }
    }

    public func validateStructuralInvariants() throws {
        try validateCoreFields()
        try validateReferenceCatalog()
        try validateSectionShape()
        try validateSectionContent()
    }

    private func validateCoreFields() throws {
        try Self.requireNonEmpty(snapshotID, field: "snapshotID")
        try Self.validateSHA256(contentSHA256, field: "contentSHA256")
        try Self.requireNonEmpty(artifactSidecarID, field: "artifactSidecarID")
        try Self.validateSHA256(artifactSidecarSHA256, field: "artifactSidecarSHA256")
        try Self.requireNonEmpty(scope.owner, field: "scope.owner")
        guard partCount > 0 else { throw Self.invalid("partCount must be positive", field: "partCount") }
        guard partIndex >= 0 else { throw Self.invalid("partIndex must be non-negative", field: "partIndex") }
        guard partIndex < partCount else { throw Self.invalid("partIndex must be less than partCount", field: "partIndex") }
    }

    private func validateReferenceCatalog() throws {
        for cid in referenceCatalog.caseIDs {
            try Self.requireNonEmpty(cid, field: "referenceCatalog.caseIDs")
        }
        guard Set(referenceCatalog.caseIDs).count == referenceCatalog.caseIDs.count else {
            throw Self.invalid("duplicate caseID in referenceCatalog", field: "referenceCatalog.caseIDs")
        }
        for eid in referenceCatalog.eventIDs {
            try Self.requireNonEmpty(eid, field: "referenceCatalog.eventIDs")
        }
        guard Set(referenceCatalog.eventIDs).count == referenceCatalog.eventIDs.count else {
            throw Self.invalid("duplicate eventID in referenceCatalog", field: "referenceCatalog.eventIDs")
        }
        for ev in referenceCatalog.evidenceRefs {
            try Self.requireNonEmpty(ev, field: "referenceCatalog.evidenceRefs")
        }
        guard Set(referenceCatalog.evidenceRefs).count == referenceCatalog.evidenceRefs.count else {
            throw Self.invalid("duplicate evidenceRef in referenceCatalog", field: "referenceCatalog.evidenceRefs")
        }
        for sid in referenceCatalog.subjectIDs {
            try Self.requireNonEmpty(sid, field: "referenceCatalog.subjectIDs")
        }
        guard Set(referenceCatalog.subjectIDs).count == referenceCatalog.subjectIDs.count else {
            throw Self.invalid("duplicate subjectID in referenceCatalog", field: "referenceCatalog.subjectIDs")
        }
        for r in referenceCatalog.revisionEvidenceRefs {
            try Self.requireNonEmpty(r, field: "referenceCatalog.revisionEvidenceRefs")
        }
        guard Set(referenceCatalog.revisionEvidenceRefs).count == referenceCatalog.revisionEvidenceRefs.count else {
            throw Self.invalid("duplicate revisionEvidenceRef in referenceCatalog", field: "referenceCatalog.revisionEvidenceRefs")
        }
        let findingFPs = referenceCatalog.findings.map(\.fingerprint)
        for fp in findingFPs {
            try Self.requireNonEmpty(fp, field: "referenceCatalog.findings.fingerprint")
        }
        guard Set(findingFPs).count == findingFPs.count else {
            throw Self.invalid("duplicate finding fingerprint in referenceCatalog", field: "referenceCatalog.findings")
        }
        let artifactIDs = referenceCatalog.artifacts.map(\.artifactID)
        for aid in artifactIDs {
            try Self.requireNonEmpty(aid, field: "referenceCatalog.artifacts.artifactID")
        }
        guard Set(artifactIDs).count == artifactIDs.count else {
            throw Self.invalid("duplicate artifactID in referenceCatalog", field: "referenceCatalog.artifacts")
        }
        for ref in referenceCatalog.artifacts {
            try Self.validateSHA256(ref.contentSHA256, field: "referenceCatalog.artifacts.contentSHA256")
            try Self.validateSHA256(ref.sidecarSHA256, field: "referenceCatalog.artifacts.sidecarSHA256")
            guard ref.sidecarID == artifactSidecarID else {
                throw Self.invalid("artifact reference sidecarID must match envelope sidecarID", field: "referenceCatalog.artifacts.sidecarID")
            }
            guard ref.sidecarSHA256 == artifactSidecarSHA256 else {
                throw Self.invalid("artifact reference sidecarSHA256 must match envelope sidecarSHA256", field: "referenceCatalog.artifacts.sidecarSHA256")
            }
        }
    }

    private func validateSectionShape() throws {
        let counts = [
            ("overview", overview != nil),
            ("findings", !findings.isEmpty),
            ("caseTimelines", !caseTimelines.isEmpty),
            ("individualMetrics", !individualMetrics.isEmpty),
            ("feedbackLineage", !feedbackLineage.isEmpty),
            ("agentRepeatMetrics", !agentRepeatMetrics.isEmpty),
            ("importObservations", !importObservations.isEmpty),
            ("artifacts", !artifacts.isEmpty)
        ]
        let populated = counts.filter { $0.1 }
        guard populated.count == 1 else {
            throw Self.invalid("exactly one section collection must be populated", field: "section")
        }
        guard populated[0].0 == section.rawValue else {
            throw Self.invalid("section discriminator does not match populated collection", field: "section")
        }
    }

    private func validateSectionContent() throws {
        switch section {
        case .overview:
            guard let overview else { throw Self.invalid("overview required", field: "overview") }
            try validateOverview(overview)
        case .findings:
            try validateFindings()
        case .caseTimelines:
            try validateCaseTimelines()
        case .individualMetrics:
            try validateIndividualMetrics()
        case .feedbackLineage:
            try validateFeedbackLineage()
        case .agentRepeatMetrics:
            try validateAgentRepeatMetrics()
        case .importObservations:
            try validateImportObservations()
        case .artifacts:
            try validateArtifacts()
        }
    }

    private func validateOverview(_ ov: DetailedOverview) throws {
        if mode == .baseline {
            guard let cohort = ov.cohort else {
                throw Self.invalid("baseline mode requires cohort", field: "overview.cohort")
            }
            guard ov.cursors.isEmpty else {
                throw Self.invalid("baseline mode must not contain cursors", field: "overview.cursors")
            }
            try Self.requireNonEmpty(cohort.cohortID, field: "overview.cohort.cohortID")
            guard !cohort.caseIDs.isEmpty else {
                throw Self.invalid("cohort caseIDs must not be empty", field: "overview.cohort.caseIDs")
            }
            guard Set(cohort.caseIDs).count == cohort.caseIDs.count else {
                throw Self.invalid("cohort caseIDs must be unique", field: "overview.cohort.caseIDs")
            }
            if cohort.caseIDs.count < 20 {
                guard !ov.limitations.isEmpty else {
                    throw Self.invalid("baseline cohort with fewer than 20 cases requires limitations", field: "overview.limitations")
                }
            }
        } else {
            guard ov.cohort == nil else {
                throw Self.invalid("incremental mode must not contain cohort", field: "overview.cohort")
            }
            guard !ov.cursors.isEmpty else {
                throw Self.invalid("incremental mode requires cursors", field: "overview.cursors")
            }
            let sourceIDs = ov.cursors.map(\.sourceID)
            for cursor in ov.cursors {
                try Self.requireNonEmpty(cursor.sourceID, field: "overview.cursors.sourceID")
                try Self.requireNonEmpty(cursor.cursorID, field: "overview.cursors.cursorID")
                guard cursor.overlapHours >= 0 else {
                    throw Self.invalid("cursor overlapHours must be non-negative", field: "overview.cursors.overlapHours")
                }
            }
            guard Set(sourceIDs).count == sourceIDs.count else {
                throw Self.invalid("cursor sourceIDs must be unique", field: "overview.cursors.sourceID")
            }
        }

        for iv in ov.instructionVersions {
            try Self.requireNonEmpty(iv.sourceID, field: "overview.instructionVersions.sourceID")
            try Self.validateSHA256(iv.sha256, field: "overview.instructionVersions.sha256")
        }

        let cov = ov.evidenceCoverage
        guard cov.requiredEvidenceCount >= 0,
              cov.availableEvidenceCount >= 0,
              cov.missingEvidenceCount >= 0,
              cov.redactedEvidenceCount >= 0 else {
            throw Self.invalid("evidence coverage counts must be non-negative", field: "overview.evidenceCoverage")
        }
        guard cov.availableEvidenceCount + cov.missingEvidenceCount == cov.requiredEvidenceCount else {
            throw Self.invalid("evidence coverage available + missing must equal required", field: "overview.evidenceCoverage")
        }
        guard cov.redactedEvidenceCount <= cov.availableEvidenceCount else {
            throw Self.invalid("redacted evidence count cannot exceed available", field: "overview.evidenceCoverage.redactedEvidenceCount")
        }
        if cov.missingEvidenceCount > 0 || cov.redactedEvidenceCount > 0 {
            guard !cov.limitations.isEmpty || !ov.limitations.isEmpty else {
                throw Self.invalid("incomplete or redacted evidence requires limitations", field: "overview.evidenceCoverage.limitations")
            }
        }

        guard ov.axisSummaries.count == 3 else {
            throw Self.invalid("overview must contain exactly three core axis summaries", field: "overview.axisSummaries")
        }
        let axes = Set(ov.axisSummaries.map(\.axis))
        guard axes == Set([.workflowConformance, .workflowFitness, .outcomeIntegrity]) else {
            throw Self.invalid("axisSummaries must contain exactly workflowConformance, workflowFitness, and outcomeIntegrity", field: "overview.axisSummaries")
        }
        for summary in ov.axisSummaries {
            guard summary.totalCases >= 0,
                  summary.positive >= 0,
                  summary.negative >= 0,
                  summary.insufficientEvidence >= 0 else {
                throw Self.invalid("axis summary counts must be non-negative", field: "overview.axisSummaries")
            }
            guard summary.positive + summary.negative + summary.insufficientEvidence == summary.totalCases else {
                throw Self.invalid("axis summary positive + negative + insufficientEvidence must equal totalCases", field: "overview.axisSummaries")
            }
        }

        let te = ov.taskEffectiveness
        guard te.totalEvaluated >= 0,
              te.effective >= 0,
              te.ineffective >= 0,
              te.regressed >= 0,
              te.pending >= 0,
              te.insufficientEvidence >= 0 else {
            throw Self.invalid("task effectiveness counts must be non-negative", field: "overview.taskEffectiveness")
        }
        guard te.effective + te.ineffective + te.regressed + te.pending + te.insufficientEvidence == te.totalEvaluated else {
            throw Self.invalid("task effectiveness breakdown must sum to totalEvaluated", field: "overview.taskEffectiveness")
        }

        if let pc = ov.publicationCoverage {
            guard pc.requiredGenericWorkflowCount >= 0,
                  pc.publishedGenericWorkflowCount >= 0,
                  pc.requiredTeamRelationshipCount >= 0,
                  pc.publishedTeamRelationshipCount >= 0,
                  pc.requiredP0P1FindingCount >= 0,
                  pc.publishedP0P1FindingCount >= 0,
                  pc.requiredP0P1ChainCount >= 0,
                  pc.publishedP0P1ChainCount >= 0,
                  pc.omittedOptionalEntityCount >= 0,
                  pc.externalizedEntityCount >= 0 else {
                throw Self.invalid("publication coverage counts must be non-negative", field: "overview.publicationCoverage")
            }
            guard pc.requiredGenericWorkflowCount == pc.publishedGenericWorkflowCount else {
                throw Self.invalid("requiredGenericWorkflowCount must equal publishedGenericWorkflowCount", field: "overview.publicationCoverage.requiredGenericWorkflowCount")
            }
            guard pc.requiredTeamRelationshipCount == pc.publishedTeamRelationshipCount else {
                throw Self.invalid("requiredTeamRelationshipCount must equal publishedTeamRelationshipCount", field: "overview.publicationCoverage.requiredTeamRelationshipCount")
            }
            guard pc.requiredP0P1FindingCount == pc.publishedP0P1FindingCount else {
                throw Self.invalid("requiredP0P1FindingCount must equal publishedP0P1FindingCount", field: "overview.publicationCoverage.requiredP0P1FindingCount")
            }
            guard pc.requiredP0P1ChainCount == pc.publishedP0P1ChainCount else {
                throw Self.invalid("requiredP0P1ChainCount must equal publishedP0P1ChainCount", field: "overview.publicationCoverage.requiredP0P1ChainCount")
            }
            if pc.omittedOptionalEntityCount > 0 || pc.externalizedEntityCount > 0 {
                guard pc.fullReport != nil else {
                    throw Self.invalid("omitted or externalized entities require full report reference", field: "overview.publicationCoverage.fullReport")
                }
            }
            if let fr = pc.fullReport {
                try Self.requireNonEmpty(fr.artifactID, field: "fullReport.artifactID")
                try Self.requireNonEmpty(fr.title, field: "fullReport.title")
                try Self.validateSHA256(fr.contentSHA256, field: "fullReport.contentSHA256")
                try Self.validateSHA256(fr.sidecarSHA256, field: "fullReport.sidecarSHA256")
                guard fr.sidecarID == artifactSidecarID else {
                    throw Self.invalid("full report sidecarID must match envelope sidecarID", field: "fullReport.sidecarID")
                }
                guard fr.sidecarSHA256 == artifactSidecarSHA256 else {
                    throw Self.invalid("full report sidecarSHA256 must match envelope sidecarSHA256", field: "fullReport.sidecarSHA256")
                }
                guard referenceCatalog.artifacts.contains(where: {
                    $0.artifactID == fr.artifactID &&
                    $0.kind == .fullReport &&
                    $0.contentSHA256 == fr.contentSHA256 &&
                    $0.sidecarID == fr.sidecarID &&
                    $0.sidecarSHA256 == fr.sidecarSHA256 &&
                    $0.url == fr.url
                }) else {
                    throw Self.invalid("full report must resolve in reference catalog", field: "overview.publicationCoverage.fullReport")
                }
            }
        }
    }

    private func validateFindings() throws {
        var fingerprints = Set<String>()
        for finding in findings {
            try Self.requireNonEmpty(finding.fingerprint, field: "findings.fingerprint")
            try Self.requireNonEmpty(finding.subjectID, field: "findings.subjectID")
            try Self.requireNonEmpty(finding.responsibilityLayer, field: "findings.responsibilityLayer")
            try Self.requireNonEmpty(finding.summary, field: "findings.summary")
            try Self.requireNonEmpty(finding.verdict, field: "findings.verdict")
            guard fingerprints.insert(finding.fingerprint).inserted else {
                throw Self.invalid("duplicate finding fingerprint: \(finding.fingerprint)", field: "findings.fingerprint")
            }
            guard referenceCatalog.findings.contains(where: { $0.fingerprint == finding.fingerprint }) else {
                throw Self.invalid("finding fingerprint must resolve in reference catalog", field: "findings.fingerprint")
            }
            guard referenceCatalog.subjectIDs.contains(finding.subjectID) else {
                throw Self.invalid("finding subjectID must resolve in reference catalog", field: "findings.subjectID")
            }
            guard !finding.caseIDs.isEmpty else {
                throw Self.invalid("finding caseIDs must not be empty", field: "findings.caseIDs")
            }
            guard Set(finding.caseIDs).isSubset(of: Set(referenceCatalog.caseIDs)) else {
                throw Self.invalid("finding caseIDs must resolve in reference catalog", field: "findings.caseIDs")
            }
            guard !finding.eventIDs.isEmpty else {
                throw Self.invalid("finding eventIDs must not be empty", field: "findings.eventIDs")
            }
            guard Set(finding.eventIDs).isSubset(of: Set(referenceCatalog.eventIDs)) else {
                throw Self.invalid("finding eventIDs must resolve in reference catalog", field: "findings.eventIDs")
            }
            guard !finding.evidenceRefs.isEmpty else {
                throw Self.invalid("finding evidenceRefs must not be empty", field: "findings.evidenceRefs")
            }
            guard Set(finding.evidenceRefs).isSubset(of: Set(referenceCatalog.evidenceRefs)) else {
                throw Self.invalid("finding evidenceRefs must resolve in reference catalog", field: "findings.evidenceRefs")
            }
        }
    }

    private func validateCaseTimelines() throws {
        var caseIDs = Set<String>()
        for timeline in caseTimelines {
            try Self.requireNonEmpty(timeline.caseID, field: "caseTimelines.caseID")
            guard caseIDs.insert(timeline.caseID).inserted else {
                throw Self.invalid("duplicate timeline caseID: \(timeline.caseID)", field: "caseTimelines.caseID")
            }
            guard referenceCatalog.caseIDs.contains(timeline.caseID) else {
                throw Self.invalid("timeline caseID must resolve in reference catalog", field: "caseTimelines.caseID")
            }
            guard timeline.events.map(\.eventID) == timeline.eventIDs else {
                throw Self.invalid("embedded events must equal eventIDs in order", field: "caseTimelines.events")
            }
            guard timeline.attempts.map(\.attemptID) == timeline.attemptIDs else {
                throw Self.invalid("embedded attempts must equal attemptIDs in order", field: "caseTimelines.attempts")
            }
            for event in timeline.events {
                try Self.requireNonEmpty(event.eventID, field: "caseTimelines.events.eventID")
                guard event.caseID == timeline.caseID else {
                    throw Self.invalid("event caseID must match containing timeline caseID", field: "caseTimelines.events.caseID")
                }
                guard referenceCatalog.eventIDs.contains(event.eventID) else {
                    throw Self.invalid("eventID must resolve in reference catalog", field: "caseTimelines.events.eventID")
                }
                guard referenceCatalog.subjectIDs.contains(event.subjectID) else {
                    throw Self.invalid("event subjectID must resolve in reference catalog", field: "caseTimelines.events.subjectID")
                }
                guard referenceCatalog.revisionEvidenceRefs.contains(event.revisionSHA) else {
                    throw Self.invalid("event revisionSHA must resolve in reference catalog", field: "caseTimelines.events.revisionSHA")
                }
                if let ev = event.evidenceRef {
                    guard referenceCatalog.evidenceRefs.contains(ev) else {
                        throw Self.invalid("event evidenceRef must resolve in reference catalog", field: "caseTimelines.events.evidenceRef")
                    }
                }
            }
            for attempt in timeline.attempts {
                try Self.requireNonEmpty(attempt.attemptID, field: "caseTimelines.attempts.attemptID")
                guard attempt.caseID == timeline.caseID else {
                    throw Self.invalid("attempt caseID must match containing timeline caseID", field: "caseTimelines.attempts.caseID")
                }
                for ev in attempt.evidenceRefs {
                    guard referenceCatalog.evidenceRefs.contains(ev) else {
                        throw Self.invalid("attempt evidenceRef must resolve in reference catalog", field: "caseTimelines.attempts.evidenceRefs")
                    }
                }
            }
        }
    }

    private func validateIndividualMetrics() throws {
        var metricIDs = Set<String>()
        for metric in individualMetrics {
            try Self.requireNonEmpty(metric.metricID, field: "individualMetrics.metricID")
            try Self.requireNonEmpty(metric.metricDefinition, field: "individualMetrics.metricDefinition")
            try Self.requireNonEmpty(metric.observationWindow, field: "individualMetrics.observationWindow")
            guard metricIDs.insert(metric.metricID).inserted else {
                throw Self.invalid("duplicate metricID: \(metric.metricID)", field: "individualMetrics.metricID")
            }
            if let den = metric.denominator {
                guard den > 0 else {
                    throw Self.invalid("metric denominator must be positive", field: "individualMetrics.denominator")
                }
            }
        }
    }

    private func validateFeedbackLineage() throws {
        var lineageIDs = Set<String>()
        for lineage in feedbackLineage {
            try Self.requireNonEmpty(lineage.problemFingerprint, field: "feedbackLineage.problemFingerprint")
            try Self.requireNonEmpty(lineage.originIssueID, field: "feedbackLineage.originIssueID")
            try Self.requireNonEmpty(lineage.deliveryIssueID, field: "feedbackLineage.deliveryIssueID")
            let preimage = lineage.problemFingerprint.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{001F}" + lineage.originIssueID.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{001F}" + lineage.deliveryIssueID.trimmingCharacters(in: .whitespacesAndNewlines)
            let computedHash = Self.computeSHA256(preimage)
            guard lineage.lineageID == computedHash else {
                throw Self.invalid("lineageID must equal canonical preimage SHA-256", field: "feedbackLineage.lineageID")
            }
            guard lineageIDs.insert(lineage.lineageID).inserted else {
                throw Self.invalid("duplicate lineageID: \(lineage.lineageID)", field: "feedbackLineage.lineageID")
            }
            if let mergeSHA = lineage.mergeSHA {
                guard Self.validateGitSHA1(mergeSHA) else {
                    throw Self.invalid("mergeSHA must be a 40 lowercase hex Git SHA-1 OID", field: "feedbackLineage.mergeSHA")
                }
            }
            guard Set(lineage.observationEventIDs).isSubset(of: Set(referenceCatalog.eventIDs)) else {
                throw Self.invalid("observationEventIDs must resolve in reference catalog", field: "feedbackLineage.observationEventIDs")
            }
        }
    }

    private func validateAgentRepeatMetrics() throws {
        var roles = Set<ActorRole>()
        for metric in agentRepeatMetrics {
            guard roles.insert(metric.actorRole).inserted else {
                throw Self.invalid("duplicate repeat metric for actorRole: \(metric.actorRole.rawValue)", field: "agentRepeatMetrics.actorRole")
            }
            guard metric.attemptsTotal >= 0,
                  metric.repeatCycles >= 0,
                  metric.repeatCases >= 0,
                  metric.sameArtifactRepeatCycles >= 0,
                  metric.changedArtifactRepeatCycles >= 0,
                  metric.maxCyclesPerCase >= 0 else {
                throw Self.invalid("repeat metric counts must be non-negative", field: "agentRepeatMetrics")
            }
            guard metric.repeatCycles <= metric.attemptsTotal else {
                throw Self.invalid("repeatCycles cannot exceed attemptsTotal", field: "agentRepeatMetrics.repeatCycles")
            }
            guard metric.repeatCases <= metric.attemptsTotal else {
                throw Self.invalid("repeatCases cannot exceed attemptsTotal", field: "agentRepeatMetrics.repeatCases")
            }
            guard metric.sameArtifactRepeatCycles + metric.changedArtifactRepeatCycles == metric.repeatCycles else {
                throw Self.invalid("sameArtifactRepeatCycles + changedArtifactRepeatCycles must equal repeatCycles", field: "agentRepeatMetrics.sameArtifactRepeatCycles")
            }
            if metric.attemptsTotal == 0 {
                guard metric.repeatCycles == 0,
                      metric.repeatCases == 0,
                      metric.sameArtifactRepeatCycles == 0,
                      metric.changedArtifactRepeatCycles == 0,
                      metric.maxCyclesPerCase == 0 else {
                    throw Self.invalid("zero attempts requires zero repeat counters", field: "agentRepeatMetrics")
                }
            }
            if !metric.byCycleKind.isEmpty {
                guard metric.byCycleKind.values.reduce(0, +) == metric.repeatCycles else {
                    throw Self.invalid("byCycleKind breakdown must sum to repeatCycles", field: "agentRepeatMetrics.byCycleKind")
                }
            }
            if !metric.byTriggerCause.isEmpty {
                guard metric.byTriggerCause.values.reduce(0, +) == metric.repeatCycles else {
                    throw Self.invalid("byTriggerCause breakdown must sum to repeatCycles", field: "agentRepeatMetrics.byTriggerCause")
                }
            }
            guard metric.roleSpecific.role == metric.actorRole else {
                throw Self.invalid("roleSpecific variant must match actorRole", field: "agentRepeatMetrics.roleSpecific")
            }

            switch metric.roleSpecific {
            case .plannerLead(let m):
                guard m.planningRevisionRounds >= 0,
                      m.planningReviewRepeatCycles >= 0,
                      m.planningSameRevisionReReviews >= 0,
                      m.planningHandoffRepeatCycles >= 0 else {
                    throw Self.invalid("plannerLead counts must be non-negative", field: "agentRepeatMetrics.roleSpecific")
                }
                guard m.planningRevisionRounds <= metric.attemptsTotal else {
                    throw Self.invalid("planningRevisionRounds cannot exceed attemptsTotal", field: "agentRepeatMetrics.roleSpecific")
                }
                if metric.attemptsTotal == 0 {
                    guard m.planningRevisionRounds == 0, m.planningReviewRepeatCycles == 0, m.planningSameRevisionReReviews == 0, m.planningHandoffRepeatCycles == 0 else {
                        throw Self.invalid("zero attempts requires zero roleSpecific counters", field: "agentRepeatMetrics.roleSpecific")
                    }
                }
            case .teamLead(let m):
                guard m.recoveryDispatchRounds >= 0,
                      m.recoveryDispatchRepeatCycles >= 0,
                      m.sameRecoveryKeyRedispatches >= 0,
                      m.ownerEscalationRepeatCycles >= 0 else {
                    throw Self.invalid("teamLead counts must be non-negative", field: "agentRepeatMetrics.roleSpecific")
                }
                guard m.recoveryDispatchRounds <= metric.attemptsTotal else {
                    throw Self.invalid("recoveryDispatchRounds cannot exceed attemptsTotal", field: "agentRepeatMetrics.roleSpecific")
                }
                if metric.attemptsTotal == 0 {
                    guard m.recoveryDispatchRounds == 0, m.recoveryDispatchRepeatCycles == 0, m.sameRecoveryKeyRedispatches == 0, m.ownerEscalationRepeatCycles == 0 else {
                        throw Self.invalid("zero attempts requires zero roleSpecific counters", field: "agentRepeatMetrics.roleSpecific")
                    }
                }
            case .fullstackEngineer(let m):
                guard m.implementationRevisionRounds >= 0,
                      m.reviewFixRounds >= 0,
                      m.ciRepairRounds >= 0,
                      m.sameReviewFindingRepeats >= 0,
                      m.sameCIFailureRepeats >= 0,
                      m.handoffRepairRounds >= 0 else {
                    throw Self.invalid("fullstackEngineer counts must be non-negative", field: "agentRepeatMetrics.roleSpecific")
                }
                guard m.implementationRevisionRounds <= metric.attemptsTotal else {
                    throw Self.invalid("implementationRevisionRounds cannot exceed attemptsTotal", field: "agentRepeatMetrics.roleSpecific")
                }
                if metric.attemptsTotal == 0 {
                    guard m.implementationRevisionRounds == 0, m.reviewFixRounds == 0, m.ciRepairRounds == 0, m.sameReviewFindingRepeats == 0, m.sameCIFailureRepeats == 0, m.handoffRepairRounds == 0 else {
                        throw Self.invalid("zero attempts requires zero roleSpecific counters", field: "agentRepeatMetrics.roleSpecific")
                    }
                }
            case .aiReviewer(let m):
                guard m.reviewRounds >= 0,
                      m.reviewRepeatCycles >= 0,
                      m.sameSHAReReviews >= 0,
                      m.changedSHAReReviews >= 0,
                      m.inconclusiveReviewRounds >= 0,
                      m.changesRequestedRounds >= 0 else {
                    throw Self.invalid("aiReviewer counts must be non-negative", field: "agentRepeatMetrics.roleSpecific")
                }
                guard m.reviewRounds <= metric.attemptsTotal else {
                    throw Self.invalid("reviewRounds cannot exceed attemptsTotal", field: "agentRepeatMetrics.roleSpecific")
                }
                if metric.attemptsTotal == 0 {
                    guard m.reviewRounds == 0, m.reviewRepeatCycles == 0, m.sameSHAReReviews == 0, m.changedSHAReReviews == 0, m.inconclusiveReviewRounds == 0, m.changesRequestedRounds == 0 else {
                        throw Self.invalid("zero attempts requires zero roleSpecific counters", field: "agentRepeatMetrics.roleSpecific")
                    }
                }
            case .prManager(let m):
                guard m.ciSupervisionRounds >= 0,
                      m.ciSupervisionRepeatCycles >= 0,
                      m.sameSHACIReruns >= 0,
                      m.shippingAttemptRounds >= 0,
                      m.shippingAttemptRepeatCycles >= 0,
                      m.implementationReturnRounds >= 0 else {
                    throw Self.invalid("prManager counts must be non-negative", field: "agentRepeatMetrics.roleSpecific")
                }
                guard m.ciSupervisionRounds <= metric.attemptsTotal,
                      m.shippingAttemptRounds <= metric.attemptsTotal else {
                    throw Self.invalid("primary rounds cannot exceed attemptsTotal", field: "agentRepeatMetrics.roleSpecific")
                }
                if metric.attemptsTotal == 0 {
                    guard m.ciSupervisionRounds == 0, m.ciSupervisionRepeatCycles == 0, m.sameSHACIReruns == 0, m.shippingAttemptRounds == 0, m.shippingAttemptRepeatCycles == 0, m.implementationReturnRounds == 0 else {
                        throw Self.invalid("zero attempts requires zero roleSpecific counters", field: "agentRepeatMetrics.roleSpecific")
                    }
                }
            }

            guard !metric.subjectIDs.isEmpty else {
                throw Self.invalid("repeat metric subjectIDs must not be empty", field: "agentRepeatMetrics.subjectIDs")
            }
            guard Set(metric.subjectIDs).isSubset(of: Set(referenceCatalog.subjectIDs)) else {
                throw Self.invalid("repeat metric subjectIDs must resolve in reference catalog", field: "agentRepeatMetrics.subjectIDs")
            }
            guard !metric.eventIDs.isEmpty else {
                throw Self.invalid("repeat metric eventIDs must not be empty", field: "agentRepeatMetrics.eventIDs")
            }
            guard Set(metric.eventIDs).isSubset(of: Set(referenceCatalog.eventIDs)) else {
                throw Self.invalid("repeat metric eventIDs must resolve in reference catalog", field: "agentRepeatMetrics.eventIDs")
            }
        }
    }

    private func validateImportObservations() throws {
        var obsIDs = Set<String>()
        for obs in importObservations {
            try Self.requireNonEmpty(obs.observationID, field: "importObservations.observationID")
            guard obs.parentSnapshotID == snapshotID else {
                throw Self.invalid("collision parentSnapshotID must match envelope snapshotID", field: "importObservations.parentSnapshotID")
            }
            guard obs.parentSnapshotSHA256 == contentSHA256 else {
                throw Self.invalid("collision parentSnapshotSHA256 must match envelope contentSHA256", field: "importObservations.parentSnapshotSHA256")
            }
            try Self.validateSHA256(obs.acceptedSHA256, field: "importObservations.acceptedSHA256")
            try Self.validateSHA256(obs.rejectedSHA256, field: "importObservations.rejectedSHA256")
            guard obs.acceptedSHA256 != obs.rejectedSHA256 else {
                throw Self.invalid("accepted and rejected SHA-256 cannot be equal", field: "importObservations.acceptedSHA256")
            }
            guard obsIDs.insert(obs.observationID).inserted else {
                throw Self.invalid("duplicate observationID: \(obs.observationID)", field: "importObservations.observationID")
            }
        }
    }

    private func validateArtifacts() throws {
        var artifactIDs = Set<String>()
        for entry in artifacts {
            try Self.requireNonEmpty(entry.artifactID, field: "artifacts.artifactID")
            try Self.requireNonEmpty(entry.title, field: "artifacts.title")
            guard entry.snapshotID == snapshotID else {
                throw Self.invalid("artifact snapshotID must match envelope snapshotID", field: "artifacts.snapshotID")
            }
            guard entry.sidecarID == artifactSidecarID else {
                throw Self.invalid("artifact sidecarID must match envelope sidecarID", field: "artifacts.sidecarID")
            }
            guard entry.sidecarSHA256 == artifactSidecarSHA256 else {
                throw Self.invalid("artifact sidecarSHA256 must match envelope sidecarSHA256", field: "artifacts.sidecarSHA256")
            }
            try Self.validateSHA256(entry.contentSHA256, field: "artifacts.contentSHA256")
            guard artifactIDs.insert(entry.artifactID).inserted else {
                throw Self.invalid("duplicate artifactID: \(entry.artifactID)", field: "artifacts.artifactID")
            }
            guard referenceCatalog.artifacts.contains(where: { $0.artifactID == entry.artifactID }) else {
                throw Self.invalid("artifactID must resolve in reference catalog", field: "artifacts.artifactID")
            }
            if let fp = entry.findingFingerprint {
                guard referenceCatalog.findings.contains(where: { $0.fingerprint == fp }) else {
                    throw Self.invalid("findingFingerprint must resolve in reference catalog", field: "artifacts.findingFingerprint")
                }
            }
            if entry.kind == .findingEventChain {
                guard entry.findingFingerprint != nil else {
                    throw Self.invalid("findingEventChain requires findingFingerprint", field: "artifacts.findingFingerprint")
                }
            }
            if let cid = entry.caseID {
                guard referenceCatalog.caseIDs.contains(cid) else {
                    throw Self.invalid("caseID must resolve in reference catalog", field: "artifacts.caseID")
                }
            }
            guard Set(entry.eventIDs).isSubset(of: Set(referenceCatalog.eventIDs)) else {
                throw Self.invalid("artifact eventIDs must resolve in reference catalog", field: "artifacts.eventIDs")
            }
            guard Set(entry.revisionEvidence).isSubset(of: Set(referenceCatalog.revisionEvidenceRefs)) else {
                throw Self.invalid("artifact revisionEvidence must resolve in reference catalog", field: "artifacts.revisionEvidence")
            }
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw invalid("missing required field value", field: field) }
    }

    private static func validateSHA256(_ value: String, field: String) throws {
        guard value.count == 64, value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw invalid("value must be exactly 64 lowercase hexadecimal characters", field: field)
        }
    }

    private static func validateGitSHA1(_ value: String) -> Bool {
        guard value.count == 40, value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            return false
        }
        return true
    }

    public static func computeSHA256(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func invalid(_ message: String, field: String) -> XPCError {
        XPCError(code: "schema.payload_decode_failed", message: message, field: field)
    }
}
