import Foundation
import Testing
@testable import AIDashCore

@Suite("TeamAuditPayload Invariant Tests")
struct TeamAuditPayloadInvariantTests {

    private let sampleSHA = String(repeating: "a", count: 64)
    private let sidecarSHA = String(repeating: "b", count: 64)

    private func makeBaseOverview() -> DetailedOverview {
        DetailedOverview(
            cohort: AuditCohort(cohortID: "cohort-1", caseIDs: (1...20).map { "case-\($0)" }),
            instructionVersions: [InstructionVersion(sourceID: "src-1", updatedAt: Date(), sha256: sampleSHA)],
            evidenceCoverage: EvidenceCoverage(requiredEvidenceCount: 10, availableEvidenceCount: 10, missingEvidenceCount: 0, redactedEvidenceCount: 0),
            axisSummaries: [
                CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 20, positive: 20, negative: 0, insufficientEvidence: 0),
                CoreAxisSummary(axis: .workflowFitness, verdict: .workflowFitness(.fit), totalCases: 20, positive: 20, negative: 0, insufficientEvidence: 0),
                CoreAxisSummary(axis: .outcomeIntegrity, verdict: .outcomeIntegrity(.intact), totalCases: 20, positive: 20, negative: 0, insufficientEvidence: 0)
            ],
            taskEffectiveness: TaskEffectivenessSummary(totalEvaluated: 20, effective: 20, ineffective: 0, regressed: 0, pending: 0, insufficientEvidence: 0),
            publicationCoverage: PublicationCoverage(
                requiredGenericWorkflowCount: 1, publishedGenericWorkflowCount: 1,
                requiredTeamRelationshipCount: 1, publishedTeamRelationshipCount: 1,
                requiredP0P1FindingCount: 1, publishedP0P1FindingCount: 1,
                requiredP0P1ChainCount: 1, publishedP0P1ChainCount: 1,
                omittedOptionalEntityCount: 0, externalizedEntityCount: 0,
                fullReport: nil
            ),
            collisionCount: 0,
            limitations: []
        )
    }

    private func makeValidPayload(
        section: TeamAuditSection = .overview,
        overview: DetailedOverview? = nil,
        findings: [AuditFinding] = [],
        caseTimelines: [AuditCaseTimeline] = [],
        individualMetrics: [IndividualMetric] = [],
        feedbackLineage: [FeedbackLineage] = [],
        agentRepeatMetrics: [AgentRepeatMetric] = [],
        importObservations: [ImportCollisionObservation] = [],
        artifacts: [ArtifactManifestEntry] = [],
        catalog: SnapshotReferenceCatalog? = nil
    ) -> TeamAuditPayload {
        let cat = catalog ?? SnapshotReferenceCatalog(
            caseIDs: (1...20).map { "case-\($0)" },
            eventIDs: ["evt-1", "evt-2"],
            evidenceRefs: ["ev-1", "ev-2"],
            subjectIDs: ["sub-1", "sub-2"],
            revisionEvidenceRefs: ["rev-1", "rev-2", String(repeating: "c", count: 40)],
            findings: [FindingReference(fingerprint: "fp-1", priority: .p0)],
            artifacts: [ArtifactReference(artifactID: "art-1", kind: .genericWorkflow, contentSHA256: sampleSHA, sidecarID: "sidecar-1", sidecarSHA256: sidecarSHA)]
        )

        return TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: AuditScope(owner: "Owner", projectID: "proj-1", repository: "repo-1"),
            mode: .baseline,
            section: section,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "sidecar-1",
            artifactSidecarSHA256: sidecarSHA,
            referenceCatalog: cat,
            overview: overview ?? (section == .overview ? makeBaseOverview() : nil),
            findings: findings,
            caseTimelines: caseTimelines,
            individualMetrics: individualMetrics,
            feedbackLineage: feedbackLineage,
            agentRepeatMetrics: agentRepeatMetrics,
            importObservations: importObservations,
            artifacts: artifacts
        )
    }

    @Test func validBaselineOverviewPasses() throws {
        let payload = makeValidPayload()
        try payload.validateInvariants()
    }

    @Test func validIncrementalOverviewPasses() throws {
        let incrementalOverview = DetailedOverview(
            cohort: nil,
            cursors: [AuditCursor(sourceID: "src-1", cursorID: "cur-1", timestamp: Date(), overlapHours: 2)],
            instructionVersions: [InstructionVersion(sourceID: "src-1", updatedAt: Date(), sha256: sampleSHA)],
            evidenceCoverage: EvidenceCoverage(requiredEvidenceCount: 5, availableEvidenceCount: 5),
            axisSummaries: [
                CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 5, positive: 5, negative: 0, insufficientEvidence: 0),
                CoreAxisSummary(axis: .workflowFitness, verdict: .workflowFitness(.fit), totalCases: 5, positive: 5, negative: 0, insufficientEvidence: 0),
                CoreAxisSummary(axis: .outcomeIntegrity, verdict: .outcomeIntegrity(.intact), totalCases: 5, positive: 5, negative: 0, insufficientEvidence: 0)
            ],
            taskEffectiveness: TaskEffectivenessSummary(totalEvaluated: 5, effective: 5, ineffective: 0, regressed: 0, pending: 0, insufficientEvidence: 0),
            limitations: []
        )
        let payload = TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: AuditScope(owner: "Owner"),
            mode: .incremental,
            section: .overview,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "sidecar-1",
            artifactSidecarSHA256: sidecarSHA,
            overview: incrementalOverview
        )
        try payload.validateInvariants()
    }

    @Test func baselineWithCursorFails() {
        let badOverview = DetailedOverview(
            cohort: AuditCohort(cohortID: "c1", caseIDs: (1...20).map { "case-\($0)" }),
            cursors: [AuditCursor(sourceID: "src-1", cursorID: "cur-1", timestamp: Date(), overlapHours: 1)],
            evidenceCoverage: EvidenceCoverage(requiredEvidenceCount: 1, availableEvidenceCount: 1),
            axisSummaries: [
                CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 1, positive: 1),
                CoreAxisSummary(axis: .workflowFitness, verdict: .workflowFitness(.fit), totalCases: 1, positive: 1),
                CoreAxisSummary(axis: .outcomeIntegrity, verdict: .outcomeIntegrity(.intact), totalCases: 1, positive: 1)
            ],
            taskEffectiveness: TaskEffectivenessSummary(totalEvaluated: 1, effective: 1)
        )
        let payload = makeValidPayload(overview: badOverview)
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func incrementalWithCohortFails() {
        let badOverview = DetailedOverview(
            cohort: AuditCohort(cohortID: "c1", caseIDs: ["case-1"]),
            cursors: [AuditCursor(sourceID: "src-1", cursorID: "cur-1", timestamp: Date(), overlapHours: 1)],
            evidenceCoverage: EvidenceCoverage(requiredEvidenceCount: 1, availableEvidenceCount: 1),
            axisSummaries: [
                CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 1, positive: 1),
                CoreAxisSummary(axis: .workflowFitness, verdict: .workflowFitness(.fit), totalCases: 1, positive: 1),
                CoreAxisSummary(axis: .outcomeIntegrity, verdict: .outcomeIntegrity(.intact), totalCases: 1, positive: 1)
            ],
            taskEffectiveness: TaskEffectivenessSummary(totalEvaluated: 1, effective: 1)
        )
        let payload = TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: AuditScope(owner: "Owner"),
            mode: .incremental,
            section: .overview,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "sidecar-1",
            artifactSidecarSHA256: sidecarSHA,
            overview: badOverview
        )
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func axisSummaryMissingCoreAxisFails() {
        let badOverview = DetailedOverview(
            cohort: AuditCohort(cohortID: "c1", caseIDs: (1...20).map { "case-\($0)" }),
            evidenceCoverage: EvidenceCoverage(requiredEvidenceCount: 1, availableEvidenceCount: 1),
            axisSummaries: [
                CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 1, positive: 1),
                CoreAxisSummary(axis: .workflowFitness, verdict: .workflowFitness(.fit), totalCases: 1, positive: 1)
            ],
            taskEffectiveness: TaskEffectivenessSummary(totalEvaluated: 1, effective: 1)
        )
        let payload = makeValidPayload(overview: badOverview)
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func axisSummaryUnreconciledCountsFail() {
        let badOverview = DetailedOverview(
            cohort: AuditCohort(cohortID: "c1", caseIDs: (1...20).map { "case-\($0)" }),
            evidenceCoverage: EvidenceCoverage(requiredEvidenceCount: 1, availableEvidenceCount: 1),
            axisSummaries: [
                CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 10, positive: 5, negative: 2, insufficientEvidence: 1),
                CoreAxisSummary(axis: .workflowFitness, verdict: .workflowFitness(.fit), totalCases: 10, positive: 10, negative: 0, insufficientEvidence: 0),
                CoreAxisSummary(axis: .outcomeIntegrity, verdict: .outcomeIntegrity(.intact), totalCases: 10, positive: 10, negative: 0, insufficientEvidence: 0)
            ],
            taskEffectiveness: TaskEffectivenessSummary(totalEvaluated: 10, effective: 10)
        )
        let payload = makeValidPayload(overview: badOverview)
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func validFindingsSectionPasses() throws {
        let finding = AuditFinding(
            fingerprint: "fp-1",
            subjectID: "sub-1",
            responsibilityLayer: "Core",
            axis: .workflowConformance,
            priority: .p0,
            verdict: "nonconformant",
            state: .open,
            summary: "P0 Finding",
            caseIDs: ["case-1"],
            eventIDs: ["evt-1"],
            evidenceRefs: ["ev-1"]
        )
        let payload = makeValidPayload(section: .findings, findings: [finding])
        try payload.validateInvariants()
    }

    @Test func validCaseTimelinesSectionPasses() throws {
        let event = AuditEvent(
            eventID: "evt-1",
            caseID: "case-1",
            source: "src",
            subjectID: "sub-1",
            actorRole: .fullstackEngineer,
            kind: "implementation",
            timestamp: Date(),
            revisionSHA: "rev-1",
            evidenceRef: "ev-1"
        )
        let attempt = AuditAttempt(
            attemptID: "att-1",
            caseID: "case-1",
            actorRole: .fullstackEngineer,
            cycle: "1",
            triggerCause: .ciCodeFailure,
            outcome: "failed",
            evidenceRefs: ["ev-1"]
        )
        let timeline = AuditCaseTimeline(
            caseID: "case-1",
            eventIDs: ["evt-1"],
            attemptIDs: ["att-1"],
            events: [event],
            attempts: [attempt]
        )
        let payload = makeValidPayload(section: .caseTimelines, caseTimelines: [timeline])
        try payload.validateInvariants()
    }

    @Test func caseTimelineMismatchedEmbeddedEventsFail() {
        let event = AuditEvent(
            eventID: "evt-2",
            caseID: "case-1",
            source: "src",
            subjectID: "sub-1",
            actorRole: .fullstackEngineer,
            kind: "impl",
            timestamp: Date(),
            revisionSHA: "rev-1"
        )
        let timeline = AuditCaseTimeline(
            caseID: "case-1",
            eventIDs: ["evt-1"],
            attemptIDs: [],
            events: [event],
            attempts: []
        )
        let payload = makeValidPayload(section: .caseTimelines, caseTimelines: [timeline])
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func validFeedbackLineagePasses() throws {
        let prob = "problem-1"
        let orig = "origin-1"
        let del = "deliv-1"
        let preimage = "\(prob)\u{001F}\(orig)\u{001F}\(del)"
        let data = Data(preimage.utf8)
        let hash = TeamAuditPayload.computeSHA256(preimage)
        let lineage = FeedbackLineage(
            lineageID: hash,
            problemFingerprint: prob,
            originIssueID: orig,
            deliveryIssueID: del,
            mergeSHA: String(repeating: "1", count: 40),
            releaseChannel: .testflight,
            observationEventIDs: ["evt-1"]
        )
        let payload = makeValidPayload(section: .feedbackLineage, feedbackLineage: [lineage])
        try payload.validateInvariants()
    }

    @Test func feedbackLineageMismatchedHashFails() {
        let lineage = FeedbackLineage(
            lineageID: String(repeating: "0", count: 64),
            problemFingerprint: "p",
            originIssueID: "o",
            deliveryIssueID: "d",
            observationEventIDs: ["evt-1"]
        )
        let payload = makeValidPayload(section: .feedbackLineage, feedbackLineage: [lineage])
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func validAgentRepeatMetricsPasses() throws {
        let metrics = AgentRepeatMetric(
            actorRole: .fullstackEngineer,
            attemptsTotal: 5,
            repeatCycles: 2,
            repeatCases: 1,
            sameArtifactRepeatCycles: 1,
            changedArtifactRepeatCycles: 1,
            maxCyclesPerCase: 2,
            byCycleKind: ["fix": 2],
            byTriggerCause: [.reviewFinding: 2],
            roleSpecific: .fullstackEngineer(FullstackEngineerRepeatMetrics(
                implementationRevisionRounds: 3,
                reviewFixRounds: 2,
                ciRepairRounds: 0,
                sameReviewFindingRepeats: 1,
                sameCIFailureRepeats: 0,
                handoffRepairRounds: 0
            )),
            subjectIDs: ["sub-1"],
            eventIDs: ["evt-1"]
        )
        let payload = makeValidPayload(section: .agentRepeatMetrics, agentRepeatMetrics: [metrics])
        try payload.validateInvariants()
    }

    @Test func agentRepeatMetricsRoleMismatchFails() {
        let metrics = AgentRepeatMetric(
            actorRole: .teamLead,
            attemptsTotal: 5,
            repeatCycles: 2,
            repeatCases: 1,
            sameArtifactRepeatCycles: 2,
            changedArtifactRepeatCycles: 0,
            roleSpecific: .fullstackEngineer(FullstackEngineerRepeatMetrics()),
            subjectIDs: ["sub-1"],
            eventIDs: ["evt-1"]
        )
        let payload = makeValidPayload(section: .agentRepeatMetrics, agentRepeatMetrics: [metrics])
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func validImportCollisionObservationPasses() throws {
        let obs = ImportCollisionObservation(
            observationID: "obs-1",
            parentSnapshotID: "snap-1",
            parentSnapshotSHA256: sampleSHA,
            observedAt: Date(),
            source: "src",
            entityKind: "snapshot",
            stableIdentity: "snap-1",
            acceptedSHA256: sampleSHA,
            rejectedSHA256: String(repeating: "f", count: 64),
            disposition: .rejectedIdentityHashCollision,
            limitation: "conflict"
        )
        let payload = makeValidPayload(section: .importObservations, importObservations: [obs])
        try payload.validateInvariants()
    }

    @Test func validArtifactsSectionPasses() throws {
        let artifact = ArtifactManifestEntry(
            artifactID: "art-1",
            snapshotID: "snap-1",
            kind: .genericWorkflow,
            title: "Workflow",
            contentSHA256: sampleSHA,
            url: "https://example.com/art",
            requirement: .mandatory,
            sidecarID: "sidecar-1",
            sidecarSHA256: sidecarSHA
        )
        let payload = makeValidPayload(section: .artifacts, artifacts: [artifact])
        try payload.validateInvariants()
    }

    @Test func wireByteLimitEnforced() throws {
        let payload = makeValidPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let validData = try encoder.encode(payload)
        #expect(validData.count <= 262_144)
        try CardType.teamAudit.validate(validData)

        let paddedData = validData + Data(repeating: UInt8(ascii: " "), count: 262_145 - validData.count + 1)
        #expect(paddedData.count > 262_144)
        #expect(throws: XPCError.self) {
            try CardType.teamAudit.validate(paddedData)
        }
    }
}
