import Foundation
import Testing
@testable import AIDashCore

@Suite("Job actions wire validation")
struct JobActionsBridgeTests {
    private let jobs: Set<String> = ["my-pr-supervisor", "pr-auto-review", "aidata-digest"]
    private func action(createdAt: Date? = Date(timeIntervalSince1970: 123.25)) -> JobActionsAction {
        JobActionsAction(id: "sample", jobID: "my-pr-supervisor", createdAt: createdAt, title: "Synthetic",
                         descriptionMd: "Safe text", controls: [
                            .init(id: "confirm", kind: .confirm, title: "Confirm"),
                            .init(id: "single", kind: .singleSelect, title: "Choose", options: ["a", "b"]),
                            .init(id: "multi", kind: .multiSelect, title: "Choose several", options: ["a", "b"]),
                            .init(id: "text", kind: .textInput, title: "Note", maxLength: 2)
                         ])
    }

    private var responses: [JobActionsResponse] {
        [.init(controlID: "confirm", value: "确认"), .init(controlID: "single", value: "a"),
         .init(controlID: "multi", value: "a,b"), .init(controlID: "text", value: "👨‍👩‍👧‍👦é")]
    }

    @Test("Canonical fields and optional date survive; revision covers timestamp precision and raw limits")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        let value = action()
        #expect(try JSONDecoder().decode(JobActionsAction.self, from: encoder.encode(value)) == value)
        #expect(try JSONDecoder().decode(JobActionsAction.self, from: encoder.encode(action(createdAt: nil))).createdAt == nil)
        let revision = try JobActionsValidation.revision(for: value)
        #expect(revision.count == 64)
        #expect(try JobActionsValidation.revision(for: action(createdAt: Date(timeIntervalSince1970: 123.5))) != revision)
        try JobActionsValidation.validateResponses(responses, for: value)
        let producerControl = Data(#"{"id":"note","kind":"textInput","title":"Note","maxLength":120}"#.utf8)
        let control = try JSONDecoder().decode(JobActionsAction.Control.self, from: producerControl)
        #expect(control.options == [])
        #expect(control.maxLength == 120)
        #expect(control.effectiveMaxLength == 80)

        let crossDeviceJSON = Data("""
        {
          "id": "linear-TIA-76",
          "jobID": "aidata-digest",
          "title": "[Bing] iOS Smart Banner / SERP",
          "description": "Clean description text",
          "status": "triage",
          "source": "Linear",
          "priority": "P0",
          "ref": "linear://TIA-76",
          "url": "https://linear.app/tianpeili/issue/TIA-76",
          "controls": [
            {"id": "decision", "kind": "singleSelect", "title": "Action", "options": ["Approve", "Done", "Dismiss"]},
            {"id": "targets", "kind": "multiSelect", "title": "选择子项", "options": ["item-a", "item-b"]},
            {"id": "note", "kind": "textInput", "title": "补充指令 / 备注（可选）", "maxLength": 80}
          ]
        }
        """.utf8)
        let crossDevice = try JSONDecoder().decode(JobActionsAction.self, from: crossDeviceJSON)
        try JobActionsValidation.validateAction(crossDevice)
        #expect(crossDevice.description == "Clean description text")
        #expect(crossDevice.descriptionMd == "Clean description text")
        #expect(crossDevice.status == "triage")
        #expect(crossDevice.source == "Linear")
        #expect(crossDevice.priority == "P0")
        #expect(crossDevice.ref == "linear://TIA-76")
        #expect(crossDevice.url == "https://linear.app/tianpeili/issue/TIA-76")
        let encodedCrossDevice = try JSONSerialization.jsonObject(
            with: encoder.encode(crossDevice)
        ) as? [String: Any]
        #expect(encodedCrossDevice?["description"] as? String == "Clean description text")
        #expect(encodedCrossDevice?["descriptionMd"] as? String == "Clean description text")
        #expect(encodedCrossDevice?["status"] as? String == "triage")
        #expect(encodedCrossDevice?["source"] as? String == "Linear")
        #expect(encodedCrossDevice?["priority"] as? String == "P0")
        #expect(encodedCrossDevice?["ref"] as? String == "linear://TIA-76")
        #expect(encodedCrossDevice?["url"] as? String == "https://linear.app/tianpeili/issue/TIA-76")
    }

    @Test("Metadata fields round-trip with snake-case wire keys and remain absent-safe")
    func metadataRoundTripAndLegacyDecode() throws {
        let value = JobActionsAction(
            id: "learning-topic-1", jobID: "aidata-digest", title: "Learn", descriptionMd: "Why now",
            source: "Learning", priority: "P1", ref: "learning-topic://topic-1",
            domain: "decisions", topicKey: "topic-1", originRef: "learning-topic://topic-1",
            revision: "3", whyNow: "New gap", sourceURI: "https://example.invalid/source",
            coverageRefs: ["vault://existing"], evidence: "sample=4", freshness: "7d CST",
            controls: []
        )
        let encoder = JSONEncoder()
        let encoded = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any]
        #expect(encoded?["topic_key"] as? String == "topic-1")
        #expect(encoded?["origin_ref"] as? String == "learning-topic://topic-1")
        #expect(encoded?["why_now"] as? String == "New gap")
        #expect(encoded?["source_uri"] as? String == "https://example.invalid/source")
        #expect(encoded?["coverage_refs"] as? [String] == ["vault://existing"])
        #expect(try JSONDecoder().decode(JobActionsAction.self, from: encoder.encode(value)) == value)

        let legacy = Data("""
        {"id":"legacy","jobID":"aidata-digest","title":"Legacy","description":"Old","controls":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(JobActionsAction.self, from: legacy)
        #expect(decoded.domain == nil)
        #expect(decoded.topicKey == nil)
        #expect(decoded.coverageRefs.isEmpty)
    }

    @Test("Linear-native attributes round-trip while legacy payloads still decode")
    func linearNativeAttributesRoundTrip() throws {
        let parent = JobActionsAction.ParentIssue(
            identifier: "TIA-83",
            title: "Parent queue",
            url: "https://linear.app/example/issue/TIA-83"
        )
        let action = JobActionsAction(
            id: "D617", jobID: "my-pr-supervisor", title: "Decision", descriptionMd: "Summary",
            labels: ["needs-decision", "testing-skill"], project: "Bing", parentIssue: parent,
            controls: [.init(id: "decision", kind: .singleSelect, title: "Choice", options: ["A", "B"])]
        )
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(JobActionsAction.self, from: encoded)
        #expect(decoded == action)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["labels"] as? [String] == ["needs-decision", "testing-skill"])
        #expect(object["project"] as? String == "Bing")
        #expect((object["parentIssue"] as? [String: Any])?["identifier"] as? String == "TIA-83")

        let legacy = Data(#"{"id":"legacy","jobID":"aidata-digest","title":"Legacy","description":"Old","controls":[]}"#.utf8)
        let legacyAction = try JSONDecoder().decode(JobActionsAction.self, from: legacy)
        #expect(legacyAction.labels.isEmpty)
        #expect(legacyAction.project == nil)
        #expect(legacyAction.parentIssue == nil)
    }

    @Test("Actionable v2 aliases decode without exposing openURL as a response control")
    func actionableV2Compatibility() throws {
        let data = Data(#"""
        {
          "id":"D617",
          "jobId":"my-pr-supervisor",
          "title":"Preserve logo aspect ratio",
          "description":"Choose the landing path",
          "status":"awaiting_owner",
          "priority":"P0",
          "source":{"kind":"pr","label":"PR & CI","url":"https://github.com/acme/repo/pull/617","entityId":"PR#617","headSha":"abc123"},
          "subCategory":"PR_DECISION",
          "worthExtracting":true,
          "controls":[
            {"id":"link","kind":"openURL","label":"Open PR","url":"https://github.com/acme/repo/pull/617"},
            {"id":"decision","kind":"singleSelect","label":"Choose","options":["Approve","Dismiss"]}
          ]
        }
        """#.utf8)
        let action = try JSONDecoder().decode(JobActionsAction.self, from: data)
        #expect(action.jobID == "my-pr-supervisor")
        #expect(action.source == "PR & CI")
        #expect(action.ref == "PR#617")
        #expect(action.url == "https://github.com/acme/repo/pull/617")
        #expect(action.controls.map(\.id) == ["decision"])
        #expect(action.controls[0].title == "Choose")
        #expect(action.subCategory == "PR_DECISION")
        try JobActionsValidation.validateAction(action)

        let noResponseAction = JobActionsAction(
            id: "link-only", jobID: "my-pr-supervisor", title: "Open", descriptionMd: "",
            url: "https://github.com/acme/repo/pull/1", controls: []
        )
        try JobActionsValidation.validateAction(noResponseAction)

    }

    @Test("Exact fields, Unicode bounds, duplicates, unknown controls, options and noncanonical selections reject")
    func invalidProposals() throws {
        let params = JobActionsPresentParams(requestID: UUID().uuidString, jobID: "my-pr-supervisor",
                                            actionID: "sample", revision: String(repeating: "a", count: 64),
                                            responses: responses)
        let data = try JSONEncoder().encode(params)
        #expect(try JobActionsValidation.decodePresent(data) == params)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["confirm"] = true
        #expect(throws: XPCError.self) {
            try JobActionsValidation.decodePresent(JSONSerialization.data(withJSONObject: object))
        }
        #expect(throws: XPCError.self) { try JobActionsValidation.decodePresent(Data(repeating: 32, count: 16385)) }
        for invalid in [
            Array(responses.dropLast()), responses + [responses[0]],
            Array(responses.dropLast()) + [.init(controlID: "other", value: "")],
            [JobActionsResponse(controlID: "confirm", value: "yes")] + Array(responses.dropFirst()),
            Array(responses.prefix(2)) + [.init(controlID: "multi", value: "b,a"), responses[3]],
            Array(responses.prefix(2)) + [.init(controlID: "multi", value: "a,a"), responses[3]],
            Array(responses.prefix(3)) + [.init(controlID: "text", value: "三字符")]
        ] {
            #expect(throws: XPCError.self) { try JobActionsValidation.validateResponses(invalid, for: action()) }
        }
        let ambiguous = JobActionsAction(id: "a", jobID: "job", title: "Synthetic", descriptionMd: "",
                                        controls: [.init(id: "multi", kind: .multiSelect, title: "Select", options: ["a,b"])])
        #expect(throws: XPCError.self) { try JobActionsValidation.validateAction(ambiguous) }
    }

    @Test("Null staging receipt is explicit and existing receipt encoding stays unchanged")
    func receiptEncoding() throws {
        let result = JobActionsPresentResult(requestID: UUID().uuidString)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        #expect(object["acknowledgement"] is NSNull)
        #expect(object["status"] as? String == "awaitingNativeConfirmation")
        let event = UserEvent(id: UUID().uuidString, timestamp: Date(), device: "synthetic",
                              cardId: "scheduled-pulse/my-pr-supervisor", action: .acknowledgeJobAction,
                              itemRef: "sample|[{\"controlID\":\"confirm\",\"value\":\"确认\"}]", cardType: "scheduledPulse")
        let decoded = try JSONDecoder().decode(UserEvent.self, from: JSONEncoder().encode(event))
        #expect(JobActionsValidation.acknowledgement(in: [decoded], for: action(), registeredJobIDs: jobs)?.id == event.id)
        let otherJob = JobActionsAction(id: "sample", jobID: "pr-auto-review", title: "Other", descriptionMd: "", controls: [])
        #expect(JobActionsValidation.acknowledgement(in: [decoded], for: otherJob, registeredJobIDs: jobs) == nil)
        let malformed = UserEvent(id: "bad", timestamp: Date(), device: "synthetic",
                                  cardId: event.cardId, action: event.action, itemRef: "sample|not-json", cardType: event.cardType)
        #expect(JobActionsValidation.acknowledgement(in: [malformed], for: action(), registeredJobIDs: jobs) == nil)
        let scoped = UserEvent(id: "scoped", timestamp: event.timestamp, device: event.device,
                               cardId: event.cardId, action: event.action,
                               itemRef: "my-pr-supervisor:\(event.itemRef ?? "")", cardType: event.cardType)
        #expect(JobActionsValidation.acknowledgement(in: [scoped], for: action(), registeredJobIDs: jobs)?.id == "scoped")
        let ambiguous = JobActionsAction(id: "my-pr-supervisor:sample", jobID: "my-pr-supervisor",
                                         title: "Not the same action", descriptionMd: "", controls: [])
        #expect(JobActionsValidation.acknowledgement(in: [scoped], for: ambiguous, registeredJobIDs: jobs) == nil)
        let forged = UserEvent(id: "forged", timestamp: event.timestamp, device: event.device,
                               cardId: event.cardId, action: event.action,
                               itemRef: "pr-auto-review:sample|[{\"controlID\":\"confirm\",\"value\":\"确认\"}]",
                               cardType: event.cardType)
        #expect(JobActionsValidation.acknowledgement(in: [forged], for: action(), registeredJobIDs: jobs) == nil)
    }
}
