#if os(macOS)
import Foundation
import AIDashCore

// MARK: - Payload Schema Descriptions

extension XPCHandlers {

    static let payloadSchemas: [String: String] = {
        var schemas: [String: String] = [:]
        schemas[CardType.metric.rawValue] = """
        {"type":"object","required":["items"],"properties":{"items":{"type":"array","minItems":1,"items":{"type":"object","required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"number"},"unit":{"type":"string"},"trend":{"type":"string","enum":["up","down","flat"]},"series":{"type":"array","items":{"type":"number"}},"ratio":{"type":"number","minimum":0,"maximum":1},"higherIsBetter":{"type":"boolean"},"context":{"type":"string"}}}}}}
        """
        schemas[CardType.insight.rawValue] = #"{"type":"object","required":["title","body"],"properties":{"title":{"type":"string","minLength":1},"subtitle":{"type":"string"},"body":{"type":"string","minLength":1},"citations":{"type":"array","items":{"type":"object","required":["label","url"],"properties":{"label":{"type":"string"},"url":{"type":"string"}}}}}}"#
        schemas[CardType.agentSummary.rawValue] = #"{"type":"object","required":["agentName","completed"],"properties":{"agentName":{"type":"string","minLength":1},"completed":{"type":"array","minItems":1,"items":{"type":"object","required":["title"],"properties":{"title":{"type":"string"},"ref":{"type":"string"}}}},"stats":{"type":"array","items":{"type":"object","required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"number"}}}}}}"#
        schemas[CardType.todoList.rawValue] = #"{"type":"object","required":["items"],"properties":{"items":{"type":"array","minItems":1,"items":{"type":"object","required":["title"],"properties":{"title":{"type":"string"},"priority":{"type":"string","enum":["low","medium","high"]},"due":{"type":"string","format":"date-time"},"ref":{"type":"string"}}}}}}"#
        schemas[CardType.trending.rawValue] = #"{"type":"object","required":["topic","items"],"properties":{"topic":{"type":"string","minLength":1},"items":{"type":"array","minItems":1,"items":{"type":"object","required":["title","url"],"properties":{"title":{"type":"string"},"url":{"type":"string"},"score":{"type":"number"},"delta":{"type":"number"},"category":{"type":"string"},"reason":{"type":"string"}}}}}}"#
        schemas[CardType.digest.rawValue] = #"{"type":"object","required":["title","body"],"properties":{"title":{"type":"string","minLength":1},"subtitle":{"type":"string"},"body":{"type":"string","minLength":1},"sections":{"type":"array","items":{"type":"object","required":["heading","paragraphs"],"properties":{"heading":{"type":"string"},"paragraphs":{"type":"array","items":{"type":"string"}}}}}}}"#
        schemas[CardType.sectionHeader.rawValue] = #"{"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1},"subtitle":{"type":"string"}}}"#
        schemas[CardType.barList.rawValue] = #"{"type":"object","required":["items"],"properties":{"items":{"type":"array","minItems":1,"items":{"type":"object","required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"number"},"valueText":{"type":"string"},"semantic":{"type":"string"}}}}}}"#
        schemas[CardType.stackedBar.rawValue] = #"{"type":"object","required":["segments"],"properties":{"title":{"type":"string"},"segments":{"type":"array","minItems":1,"items":{"type":"object","required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"number"},"semantic":{"type":"string"}}}}}}"#
        schemas[CardType.relationship.rawValue] = relationshipSchema
        return schemas
    }()

    /// The `allOf`/`if`-`then` clauses mirror `validateMarkSet`, so a publisher
    /// reading `aidash schema list` sees the exclusivity `card.put` enforces.
    /// Fields that `validateInvariants()` runs through `requireText` advertise
    /// `"pattern":"\\S"`, not `minLength:1` — `requireText` trims first, so
    /// `"   "` is one character long and still rejected, and `minLength:1`
    /// would advertise as valid a payload the app refuses. Split for line len.
    private static let relationshipSchema =
        #"{"type":"object","required":["title","visualization","xAxis","yAxis","sampleSize","timeWindow","metricDefinition","summary"],"properties":{"title":{"type":"string","pattern":"\\S"},"visualization":{"type":"string","enum":["scatter","heatmap","slope"]},"xAxis":{"type":"object","required":["label"],"properties":{"label":{"type":"string","pattern":"\\S"},"unit":{"type":"string"}}},"# +
        #""yAxis":{"type":"object","required":["label"],"properties":{"label":{"type":"string","pattern":"\\S"},"unit":{"type":"string"}}},"points":{"type":"array","items":{"type":"object","required":["label","x","y"],"properties":{"label":{"type":"string","pattern":"\\S"},"x":{"type":"number"},"y":{"type":"number"},"magnitude":{"type":"number","exclusiveMinimum":0},"category":{"type":"string"}}}},"# +
        #""cells":{"type":"array","items":{"type":"object","required":["column","row","value"],"properties":{"column":{"type":"string","pattern":"\\S"},"row":{"type":"string","pattern":"\\S"},"value":{"type":"number"}}}},"slopes":{"type":"array","items":{"type":"object","required":["label","before","after"],"properties":{"label":{"type":"string","pattern":"\\S"},"before":{"type":"number"},"after":{"type":"number"}}}},"# +
        #""sampleSize":{"type":"integer","minimum":1},"timeWindow":{"type":"string","pattern":"\\S"},"metricDefinition":{"type":"string","pattern":"\\S"},"summary":{"type":"string","pattern":"\\S"}},"allOf":[{"if":{"properties":{"visualization":{"const":"scatter"}}},"then":{"required":["points"],"properties":{"points":{"minItems":1},"cells":{"maxItems":0},"slopes":{"maxItems":0}}}},{"if":{"properties":{"visualization":{"const":"heatmap"}}},"# +
        #""then":{"required":["cells"],"properties":{"cells":{"minItems":1},"points":{"maxItems":0},"slopes":{"maxItems":0}}}},{"if":{"properties":{"visualization":{"const":"slope"}}},"then":{"required":["slopes"],"properties":{"slopes":{"minItems":1},"points":{"maxItems":0},"cells":{"maxItems":0}}}}]}"#

    // MARK: - Schema Handlers

    func handleSchemaList(_ request: XPCRequest) throws -> Data {
        let result = SchemaListResult(
            cliVersion: Self.appVersion,
            schemaVersion: "1.0.0",
            cardTypes: CardType.allCases.map(\.rawValue),
            cardSizes: CardSize.allCases.map(\.rawValue),
            cardStyles: CardStyle.allCases.map(\.rawValue),
            containerLayouts: ContainerLayout.allCases.map(\.rawValue),
            userEventActions: UserEventAction.allCases.map(\.rawValue),
            payloads: Self.payloadSchemas
        )
        return try makeXPCEncoder().encode(result)
    }

    /// Nonisolated schema list builder for the fast path in `execute()`.
    /// Returns a complete XPCResponse without needing MainActor or the container.
    nonisolated static func buildSchemaListResponse(requestId: String) -> XPCResponse {
        let result = SchemaListResult(
            cliVersion: appVersion,
            schemaVersion: "1.0.0",
            cardTypes: CardType.allCases.map(\.rawValue),
            cardSizes: CardSize.allCases.map(\.rawValue),
            cardStyles: CardStyle.allCases.map(\.rawValue),
            containerLayouts: ContainerLayout.allCases.map(\.rawValue),
            userEventActions: UserEventAction.allCases.map(\.rawValue),
            payloads: payloadSchemas
        )
        let data = try? makeXPCEncoder().encode(result)
        return XPCResponse(
            requestId: requestId,
            appVersion: appVersion,
            ok: true,
            data: data,
            error: nil
        )
    }
}
#endif
