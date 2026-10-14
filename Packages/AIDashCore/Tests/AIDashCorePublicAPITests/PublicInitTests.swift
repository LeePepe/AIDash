import Foundation
import Testing
import AIDashCore

@Suite("Public API — Memberwise Init Accessibility")
struct PublicInitTests {

    @Test func cardPublicInit() {
        let card = Card(
            id: "x",
            type: .metric,
            size: .small,
            style: .neutral,
            payload: Data()
        )
        #expect(card.id == "x")
    }

    @Test func containerPublicInit() {
        let container = Container(
            id: "x",
            title: "t",
            subtitle: nil,
            order: 0,
            layout: .auto,
            style: .neutral,
            cards: []
        )
        #expect(container.id == "x")
    }

    @Test func briefingPublicInit() {
        let briefing = Briefing(
            date: "2026-01-01",
            generatedAt: Date(),
            generatedBy: "test",
            containers: []
        )
        #expect(briefing.date == "2026-01-01")
    }

    @Test func userEventPublicInit() {
        let event = UserEvent(
            id: "x",
            timestamp: Date(),
            device: "d",
            cardId: "c",
            action: .done
        )
        #expect(event.id == "x")
    }

    /// The bar-list header anchor must be reachable from outside the module:
    /// AIDashUI builds the card's header band from `headerTitle`, and the
    /// `title:` argument must stay defaulted so existing call sites that pass
    /// only `items:` keep compiling.
    @Test func barListPayloadPublicHeaderAnchor() {
        let untitled = BarListPayload(items: [.init(label: "AIDash", value: 48)])
        #expect(untitled.title == nil)
        #expect(untitled.headerTitle == nil)

        let titled = BarListPayload(
            items: [.init(label: "AIDash", value: 48)],
            title: "提交排行"
        )
        #expect(titled.headerTitle == "提交排行")
    }

    @Test func teamAuditPublicInits() {
        let sampleSHA = String(repeating: "a", count: 64)
        let sidecarSHA = String(repeating: "b", count: 64)

        let scope = AuditScope(owner: "Owner", projectID: "p1", repository: "r1")
        let cohort = AuditCohort(cohortID: "c1", caseIDs: ["case-1"])
        let cursor = AuditCursor(sourceID: "src-1", cursorID: "cur-1", timestamp: Date(), overlapHours: 0)
        let iv = InstructionVersion(sourceID: "src-1", updatedAt: Date(), sha256: sampleSHA)
        let cov = EvidenceCoverage(requiredEvidenceCount: 1, availableEvidenceCount: 1)
        let summary = CoreAxisSummary(axis: .workflowConformance, verdict: .workflowConformance(.conformant), totalCases: 1, positive: 1)
        let te = TaskEffectivenessSummary(totalEvaluated: 1, effective: 1)
        let fr = FullReportReference(artifactID: "art-1", title: "Report", contentSHA256: sampleSHA, url: "https://example.com", sidecarID: "side-1", sidecarSHA256: sidecarSHA)
        let pc = PublicationCoverage(fullReport: fr)
        let overview = DetailedOverview(
            cohort: cohort,
            cursors: [cursor],
            instructionVersions: [iv],
            evidenceCoverage: cov,
            axisSummaries: [summary],
            taskEffectiveness: te,
            publicationCoverage: pc,
            collisionCount: 0,
            limitations: ["lim"]
        )

        let finding = AuditFinding(
            fingerprint: "fp-1",
            subjectID: "sub-1",
            responsibilityLayer: "Core",
            axis: .workflowConformance,
            priority: .p0,
            verdict: "conformant",
            state: .open,
            summary: "summary",
            caseIDs: ["case-1"],
            eventIDs: ["evt-1"],
            evidenceRefs: ["ev-1"],
            remediationOwner: .projectDevTeam
        )

        let event = AuditEvent(
            eventID: "evt-1",
            caseID: "case-1",
            source: "src",
            subjectID: "sub-1",
            actorRole: .fullstackEngineer,
            kind: "impl",
            timestamp: Date(),
            revisionSHA: String(repeating: "1", count: 40),
            evidenceRef: "ev-1"
        )

        let attempt = AuditAttempt(
            attemptID: "att-1",
            caseID: "case-1",
            actorRole: .fullstackEngineer,
            cycle: "1",
            triggerCause: .planningFinding,
            outcome: "pass",
            evidenceRefs: ["ev-1"]
        )

        let timeline = AuditCaseTimeline(
            caseID: "case-1",
            eventIDs: ["evt-1"],
            attemptIDs: ["att-1"],
            events: [event],
            attempts: [attempt],
            limitations: []
        )

        let metric = IndividualMetric(
            metricID: "m1",
            metricDefinition: "def",
            numerator: 10,
            denominator: 20,
            observationWindow: "7d",
            limitation: nil
        )

        let lineage = FeedbackLineage(
            lineageID: sampleSHA,
            problemFingerprint: "fp",
            originIssueID: "orig",
            deliveryIssueID: "del",
            prURL: "https://example.com/pr",
            mergeSHA: String(repeating: "2", count: 40),
            releaseChannel: .testflight,
            taskEffectiveness: .effective
        )

        let plannerLeadMetrics = PlannerLeadRepeatMetrics()
        _ = TeamLeadRepeatMetrics()
        _ = FullstackEngineerRepeatMetrics()
        _ = AIReviewerRepeatMetrics()
        _ = PRManagerRepeatMetrics()

        let repeatMetric = AgentRepeatMetric(
            actorRole: .plannerLead,
            attemptsTotal: 1,
            roleSpecific: .plannerLead(plannerLeadMetrics),
            subjectIDs: ["sub-1"],
            eventIDs: ["evt-1"]
        )

        let obs = ImportCollisionObservation(
            observationID: "obs-1",
            parentSnapshotID: "snap-1",
            parentSnapshotSHA256: sampleSHA,
            observedAt: Date(),
            source: "src",
            entityKind: "kind",
            stableIdentity: "id",
            acceptedSHA256: sampleSHA,
            rejectedSHA256: sidecarSHA,
            disposition: .rejectedIdentityHashCollision,
            limitation: "lim"
        )

        let artifact = ArtifactManifestEntry(
            artifactID: "art-1",
            snapshotID: "snap-1",
            kind: .genericWorkflow,
            title: "Workflow",
            contentSHA256: sampleSHA,
            url: "https://example.com/art",
            requirement: .mandatory,
            sidecarID: "side-1",
            sidecarSHA256: sidecarSHA
        )

        let grill = GrillLinks(grillMeURL: "https://example.com", sidecarID: "side-1", sidecarSHA256: sidecarSHA)
        let ext = ExternalizedEntityReference(entityKind: .p2Finding, stableID: "p2", encodedByteCount: 100, sidecarID: "side-1", sidecarSHA256: sidecarSHA, fullReport: fr)
        _ = ArtifactSection(entries: [artifact], fullReport: fr, externalizedEntities: [ext], grillLinks: grill)

        let catalog = SnapshotReferenceCatalog(
            caseIDs: ["case-1"],
            eventIDs: ["evt-1"],
            evidenceRefs: ["ev-1"],
            subjectIDs: ["sub-1"],
            revisionEvidenceRefs: [String(repeating: "1", count: 40)],
            findings: [FindingReference(fingerprint: "fp-1", priority: .p0)],
            artifacts: [ArtifactReference(artifactID: "art-1", kind: .genericWorkflow, contentSHA256: sampleSHA, sidecarID: "side-1", sidecarSHA256: sidecarSHA)]
        )

        let payload = TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: scope,
            mode: .baseline,
            section: .overview,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "side-1",
            artifactSidecarSHA256: sidecarSHA,
            referenceCatalog: catalog,
            overview: overview,
            findings: [finding],
            caseTimelines: [timeline],
            individualMetrics: [metric],
            feedbackLineage: [lineage],
            agentRepeatMetrics: [repeatMetric],
            importObservations: [obs],
            artifacts: [artifact]
        )

        #expect(payload.snapshotID == "snap-1")
    }
}
