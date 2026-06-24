public struct AgentSummaryPayload: CardPayloadProtocol {
    public struct Completed: Codable, Sendable {
        public let title: String
        public let ref: String?

        public init(title: String, ref: String? = nil) {
            self.title = title
            self.ref = ref
        }
    }

    public struct Stat: Codable, Sendable {
        public let label: String
        public let value: Double

        public init(label: String, value: Double) {
            self.label = label
            self.value = value
        }
    }

    public let agentName: String
    public let completed: [Completed]
    public let stats: [Stat]?

    public init(agentName: String, completed: [Completed], stats: [Stat]? = nil) {
        self.agentName = agentName
        self.completed = completed
        self.stats = stats
    }

    public func validateInvariants() throws {
        if agentName.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "AgentSummaryPayload requires non-empty agentName",
                field: "agentName"
            )
        }
        guard !completed.isEmpty else {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "AgentSummaryPayload requires at least one completed item",
                field: "completed"
            )
        }
    }
}
