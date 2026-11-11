#if os(macOS)
import Foundation
import SwiftData
import Testing
import AIDashCore
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
private final class ReviewPresenterFixture: JobActionsReviewPresenting {
    var reviews: [JobActionsReviewModel] = []
    var confirmations: [() -> Void] = []
    var cancellations: [() -> Void] = []
    var focused = 0
    var closed = 0

    func present(_ review: JobActionsReviewModel, confirm: @escaping @MainActor () -> Void,
                 cancel: @escaping @MainActor () -> Void) throws {
        reviews.append(review)
        confirmations.append(confirm)
        cancellations.append(cancel)
    }

    func focus(requestID: String) { focused += 1 }
    func close(requestID: String) { closed += 1 }
}

@MainActor
private final class ActionBridgeFixture {
    let presenter = ReviewPresenterFixture()
    var actions = [ActionBridgeFixture.action()]
    var diagnostics: [JobActionsDiagnostic] = []
    var events: [UserEvent] = []
    var saves = 0
    var failSave = false
    var failRead = false
    var nativeAvailable = true
    var now = Date(timeIntervalSince1970: 1000)
    lazy var bridge = JobActionsBridge(
        registeredJobIDs: Set(ScheduledPulseRegistry.jobs.map { $0.id.rawValue }),
        readSources: { [unowned self] in .init(actions: actions, diagnostics: diagnostics) },
        readReceipts: { [unowned self] in
            if failRead { throw JobActionsBridgeError.make("bridge-unavailable") }
            return events
        },
        recordReceipt: { [unowned self] action, responses in
            if failSave { throw JobActionsBridgeError.make("persistence-failed") }
            saves += 1
            let event = try Self.receipt(action, responses: responses)
            events.append(event)
            return event
        },
        nativeAvailable: { [unowned self] in nativeAvailable },
        presenter: presenter, now: { [unowned self] in now }
    )

    static func action(job: String = "my-pr-supervisor", title: String = "Synthetic action") -> JobActionsAction {
        JobActionsAction(id: "sample", jobID: job, title: title, descriptionMd: "Synthetic only",
                         controls: [.init(id: "confirm", kind: .confirm, title: "Confirm")])
    }

    static func receipt(_ action: JobActionsAction, responses: [JobActionsResponse]) throws -> UserEvent {
        let json = String(decoding: try JSONEncoder().encode(responses), as: UTF8.self)
        return UserEvent(id: UUID().uuidString, timestamp: Date(timeIntervalSince1970: 1000), device: "synthetic",
                         cardId: "scheduled-pulse/\(action.jobID)", action: .acknowledgeJobAction,
                         itemRef: "\(action.jobID):\(action.id)|\(json)", cardType: "scheduledPulse")
    }

    func proposal(action: JobActionsAction? = nil, requestID: String = UUID().uuidString) throws -> JobActionsPresentParams {
        let value = action ?? actions[0]
        return JobActionsPresentParams(requestID: requestID, jobID: value.jobID, actionID: value.id,
                                       revision: try JobActionsValidation.revision(for: value),
                                       responses: [.init(controlID: "confirm", value: "确认")])
    }
}

@MainActor
@Suite("Native action receipt bridge")
struct JobActionsAppBridgeTests {
    @Test("Present stages once, identical requests focus, native double taps save once and snapshot reads actual receipt")
    func nativeOnlyAndIdempotent() throws {
        let fixture = ActionBridgeFixture()
        let proposal = try fixture.proposal(requestID: "abcdefab-0000-4000-8000-abcdefabcdef")
        let presented = try fixture.bridge.present(proposal)
        #expect(presented.status == .awaitingNativeConfirmation)
        #expect(presented.requestID == proposal.requestID)
        #expect(try fixture.bridge.present(proposal).acknowledgement == nil)
        #expect(fixture.saves == 0)
        #expect(fixture.presenter.reviews.count == 1)
        #expect(fixture.presenter.focused == 1)
        fixture.presenter.confirmations[0]()
        fixture.presenter.confirmations[0]()
        #expect(fixture.saves == 1)
        #expect(fixture.presenter.reviews[0].phase == .recorded)
        let snapshot = try fixture.bridge.snapshot()
        #expect(snapshot.entries[0].acknowledgement?.id == fixture.events[0].id)
        let repeated = try fixture.bridge.present(proposal)
        #expect(repeated.status == .acknowledged)
        #expect(repeated.acknowledgement?.id == fixture.events[0].id)
        #expect(fixture.presenter.reviews.count == 1)
    }

    @Test("Cancel/close and timeout cannot save even if an old native callback fires")
    func cancelAndExpire() throws {
        let fixture = ActionBridgeFixture()
        let proposal = try fixture.proposal()
        _ = try fixture.bridge.present(proposal)
        fixture.presenter.cancellations[0]()
        fixture.presenter.confirmations[0]()
        #expect(fixture.events.isEmpty)
        #expect(throws: XPCError.self) { try fixture.bridge.present(proposal) }
        _ = try fixture.bridge.present(fixture.proposal())
        fixture.now = fixture.now.addingTimeInterval(301)
        _ = try fixture.bridge.snapshot()
        fixture.presenter.confirmations[1]()
        #expect(fixture.presenter.closed == 2)
        #expect(fixture.events.isEmpty)
    }

    @Test("An expired native callback cannot confirm a newly restaged identical UUID")
    func expiredCallbackIdentity() throws {
        let fixture = ActionBridgeFixture()
        let proposal = try fixture.proposal()
        _ = try fixture.bridge.present(proposal)
        fixture.now = fixture.now.addingTimeInterval(301)
        _ = try fixture.bridge.present(proposal)
        fixture.presenter.confirmations[0]()
        #expect(fixture.events.isEmpty)
        fixture.presenter.confirmations[1]()
        #expect(fixture.events.count == 1)
    }

    @Test("Invalid, unknown, stale and conflicting requests never present; current revision is rechecked at native tap")
    func rejectsWithoutSideEffects() throws {
        let fixture = ActionBridgeFixture()
        let proposal = try fixture.proposal()
        let otherJob = ActionBridgeFixture.action(job: "not-registered")
        #expect(throws: XPCError.self) { try fixture.bridge.present(fixture.proposal(action: otherJob)) }
        let changed = ActionBridgeFixture.action(title: "Changed")
        #expect(throws: XPCError.self) { try fixture.bridge.present(fixture.proposal(action: changed)) }
        let invalid = JobActionsPresentParams(requestID: proposal.requestID, jobID: proposal.jobID,
                                              actionID: proposal.actionID, revision: proposal.revision,
                                              responses: [.init(controlID: "confirm", value: "not-confirmed")])
        #expect(throws: XPCError.self) { try fixture.bridge.present(invalid) }
        #expect(fixture.presenter.reviews.isEmpty)
        _ = try fixture.bridge.present(proposal)
        #expect(throws: XPCError.self) {
            try fixture.bridge.present(fixture.proposal(action: changed, requestID: proposal.requestID))
        }
        fixture.actions = [changed]
        fixture.presenter.confirmations[0]()
        #expect(fixture.presenter.reviews[0].phase == .stale)
        #expect(fixture.events.isEmpty)
    }

    @Test("Persistence failure retains draft, retry records, and two native windows cannot duplicate a receipt")
    func failureAndTwoWindows() throws {
        let fixture = ActionBridgeFixture()
        _ = try fixture.bridge.present(fixture.proposal())
        _ = try fixture.bridge.present(fixture.proposal())
        fixture.failSave = true
        fixture.presenter.confirmations[0]()
        #expect(fixture.presenter.reviews[0].phase == .failed("persistence-failed"))
        #expect(fixture.presenter.reviews[0].proposal.responses[0].value == "确认")
        #expect(fixture.events.isEmpty)
        fixture.failSave = false
        fixture.presenter.confirmations[0]()
        fixture.presenter.confirmations[1]()
        #expect(fixture.events.count == 1)
        #expect(fixture.presenter.reviews.allSatisfy { $0.phase == .recorded })
    }

    @Test("Exact cross-job receipt scope; unrelated missing files remain diagnostic without disabling valid presentation")
    func partialSourceAndCrossJobScope() throws {
        let fixture = ActionBridgeFixture()
        fixture.diagnostics = [.init(code: "source-missing", jobID: "aidata-digest")]
        fixture.events = [try ActionBridgeFixture.receipt(
            ActionBridgeFixture.action(job: "pr-auto-review"), responses: [.init(controlID: "confirm", value: "确认")]
        )]
        let snapshot = try fixture.bridge.snapshot()
        #expect(snapshot.capabilities.present)
        #expect(snapshot.entries[0].acknowledgement == nil)
        #expect(snapshot.diagnostics[0].jobID == "aidata-digest")
        #expect(try fixture.bridge.present(fixture.proposal()).status == .awaitingNativeConfirmation)
        fixture.diagnostics.append(.init(code: "source-missing", jobID: "my-pr-supervisor"))
        #expect(throws: XPCError.self) { try fixture.bridge.present(fixture.proposal()) }
        fixture.diagnostics.removeLast()
        fixture.failRead = true
        let unavailable = try fixture.bridge.snapshot()
        #expect(!unavailable.capabilities.present)
        #expect(unavailable.diagnostics.contains { $0.code == "store-unavailable" })
        fixture.presenter.confirmations[0]()
        #expect(fixture.events.count == 1)
        #expect(fixture.presenter.reviews[0].phase == .failed("bridge-unavailable"))
    }

    @Test("No UI capability is explicit, and the ephemeral stage count is bounded")
    func unavailableAndBounded() throws {
        let fixture = ActionBridgeFixture()
        fixture.nativeAvailable = false
        #expect(try !fixture.bridge.snapshot().capabilities.present)
        #expect(throws: XPCError.self) { try fixture.bridge.present(fixture.proposal()) }
        fixture.nativeAvailable = true
        for _ in 0..<16 { _ = try fixture.bridge.present(fixture.proposal()) }
        #expect(throws: XPCError.self) { try fixture.bridge.present(fixture.proposal()) }
        #expect(fixture.events.isEmpty)
    }

    @Test("Registered source parsing preserves fractional createdAt and limits, rejects partial controls and duplicate IDs")
    func sourceValidation() throws {
        let source = Data(#"{"id":"sample","jobID":"my-pr-supervisor","createdAt":"2026-11-11T08:00:00.123Z","title":"Synthetic","description":"Text","status":"triage","source":"Linear","priority":"P0","ref":"linear://TIA-76","url":"https://linear.app/tianpeili/issue/TIA-76","controls":[{"id":"note","kind":"textInput","title":"Note","maxLength":120}]}"#.utf8)
        let parsed = try #require(JobActionsSources.decode(source, jobID: "my-pr-supervisor").first)
        #expect(parsed.createdAt != nil)
        #expect(parsed.description == "Text")
        #expect(parsed.descriptionMd == "Text")
        #expect(parsed.status == "triage")
        #expect(parsed.source == "Linear")
        #expect(parsed.priority == "P0")
        #expect(parsed.ref == "linear://TIA-76")
        #expect(parsed.url == "https://linear.app/tianpeili/issue/TIA-76")
        #expect(parsed.controls[0].maxLength == 120)
        #expect(parsed.controls[0].effectiveMaxLength == 80)
        #expect(throws: (any Error).self) { try JobActionsSources.decode(source, jobID: "pr-auto-review") }
        #expect(throws: (any Error).self) {
            try JobActionsSources.decode(source + Data("\n".utf8) + source, jobID: "my-pr-supervisor")
        }
        let malformed = Data(#"{"id":"bad","jobID":"my-pr-supervisor","title":"Synthetic","descriptionMd":"","controls":[{"id":"x","kind":"futureKind","title":"Unknown"}]}"#.utf8)
        #expect(throws: (any Error).self) { try JobActionsSources.decode(malformed, jobID: "my-pr-supervisor") }
        let snapshot = JobActionsSources.load(
            home: URL(fileURLWithPath: "/synthetic-home"), jobs: ScheduledPulseRegistry.jobs
        ) { url, limit in
            #expect(limit == JobActionsSources.maximumFileBytes + 1)
            if url.path.contains("my-pr-supervisor") { return source }
            if url.path.contains("pr-auto-review") { throw CocoaError(.fileReadNoSuchFile) }
            return Data(repeating: 32, count: limit)
        }
        #expect(snapshot.actions.count == 1)
        #expect(snapshot.diagnostics.map(\.code) == ["source-missing", "source-oversized"])
    }

    @Test("Actual existing UserEvent save and encoding are exercised only in memory")
    func inMemoryWriter() throws {
        let container = try ModelContainer(for: UserEventModel.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let writer = UserEventWriter(container: container)
        let action = ActionBridgeFixture.action()
        let responses = [JobActionsResponse(controlID: "confirm", value: "确认")]
        let event = try writer.recordReviewedJobAction(action: action, responses: responses, device: "synthetic")
        let duplicate = try writer.recordReviewedJobAction(action: action, responses: responses, device: "synthetic")
        #expect(duplicate.id == event.id)
        let rows = try ModelContext(container).fetch(FetchDescriptor<UserEventModel>())
        #expect(rows.count == 1)
        #expect(rows[0].itemRef?.hasPrefix("my-pr-supervisor:sample|") == true)
        let encoded = try makeXPCEncoder().encode(event)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == Set(["id", "timestamp", "device", "cardId", "action", "itemRef", "cardType"]))
        #expect(object["action"] as? String == "acknowledgeJobAction")
        #expect(object["cardType"] as? String == "scheduledPulse")
    }

    @Test("Public XPC dispatch stages through injected adapters and returns receipt only after synthetic native tap")
    func injectedXPCDispatch() async throws {
        let fixture = ActionBridgeFixture()
        let handlers = XPCHandlers(container: nil)
        handlers.jobActionsBridge = fixture.bridge
        let snapshotResponse = try await XPCTestSupport.send(handlers, command: "job-actions.snapshot", params: [String: String]())
        let snapshot = try XPCTestSupport.decodeResult(JobActionsSnapshot.self, from: snapshotResponse)
        #expect(snapshotResponse.ok)
        #expect(snapshot.entries.count == 1)
        let response = try await XPCTestSupport.send(handlers, command: "job-actions.present", params: fixture.proposal())
        #expect(response.ok)
        let result = try XPCTestSupport.decodeResult(JobActionsPresentResult.self, from: response)
        #expect(result.status == .awaitingNativeConfirmation)
        #expect(fixture.events.isEmpty)
        fixture.presenter.confirmations[0]()
        #expect(fixture.events.count == 1)
        let bad = try await XPCTestSupport.send(handlers, command: "job-actions.present", params: ["confirm": true])
        #expect(!bad.ok)
        #expect(bad.error?.code == "schema.invalid-request")
    }

    @Test("Unicode multi-select matches NFC scalar ordering, rejects UTF16 order and respects grapheme text limits")
    func unicodeResponses() throws {
        let action = JobActionsAction(id: "sample", jobID: "my-pr-supervisor", title: "Synthetic", descriptionMd: "",
                                      controls: [
                                        .init(id: "multi", kind: .multiSelect, title: "Select", options: ["😀", "\u{e000}", "e\u{301}"]),
                                        .init(id: "note", kind: .textInput, title: "Note", maxLength: 1)
                                      ])
        try JobActionsValidation.validateResponses([
            .init(controlID: "multi", value: "e\u{301},\u{e000},😀"), .init(controlID: "note", value: "👨‍👩‍👧‍👦")
        ], for: action)
        #expect(throws: XPCError.self) {
            try JobActionsValidation.validateResponses([
                .init(controlID: "multi", value: "e\u{301},😀,\u{e000}"), .init(controlID: "note", value: "👨‍👩‍👧‍👦")
            ], for: action)
        }
    }
}
#endif
