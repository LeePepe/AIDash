#if os(macOS)
import Foundation
import SwiftData
import AIDashCore

/// Handles incoming XPC requests from the `aidash` CLI.
/// Dispatches commands to typed handlers, validates inputs, and performs SwiftData mutations.
@MainActor
final class XPCHandlers: NSObject, AIDashXPCServiceProtocol {

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
    }

    // MARK: - AIDashXPCServiceProtocol

    nonisolated func execute(requestData: Data, reply: @escaping (Data) -> Void) {
        nonisolated(unsafe) let reply = reply
        Task { @MainActor in
            let response = await self.handleRequest(requestData)
            let encoded = (try? JSONEncoder.xpc.encode(response)) ?? Data()
            reply(encoded)
        }
    }

    // MARK: - Request Routing

    private func handleRequest(_ data: Data) async -> XPCResponse {
        let requestId: String
        do {
            let request = try JSONDecoder.xpc.decode(XPCRequest.self, from: data)
            requestId = request.requestId
            let resultData = try await dispatch(request)
            return XPCResponse(
                requestId: requestId,
                appVersion: Self.appVersion,
                ok: true,
                data: resultData,
                error: nil
            )
        } catch let error as XPCError {
            return XPCResponse(
                requestId: (try? JSONDecoder.xpc.decode(XPCRequest.self, from: data).requestId) ?? "",
                appVersion: Self.appVersion,
                ok: false,
                data: nil,
                error: error
            )
        } catch is DecodingError {
            return XPCResponse(
                requestId: (try? JSONDecoder.xpc.decode(XPCRequest.self, from: data).requestId) ?? "",
                appVersion: Self.appVersion,
                ok: false,
                data: nil,
                error: XPCError(
                    code: "schema.payload_decode_failed",
                    message: "Failed to decode request envelope"
                )
            )
        } catch {
            let code: String
            if String(describing: error).contains("SwiftData") ||
               String(describing: error).contains("ModelContext") ||
               String(describing: error).contains("PersistentModel") {
                code = "internal.swiftdata_error"
            } else {
                code = "internal.unexpected"
            }
            return XPCResponse(
                requestId: (try? JSONDecoder.xpc.decode(XPCRequest.self, from: data).requestId) ?? "",
                appVersion: Self.appVersion,
                ok: false,
                data: nil,
                error: XPCError(
                    code: code,
                    message: "An internal error occurred"
                )
            )
        }
    }

    private func dispatch(_ request: XPCRequest) async throws -> Data? {
        switch request.command {
        case "ping":
            return nil
        case "briefing.put":
            return try await handleBriefingPut(request)
        case "briefing.publish":
            return try await handleBriefingPublish(request)
        case "briefing.get":
            return try await handleBriefingGet(request)
        case "container.put":
            return try await handleContainerPut(request)
        case "container.delete":
            return try await handleContainerDelete(request)
        case "card.put":
            return try await handleCardPut(request)
        case "card.delete":
            return try await handleCardDelete(request)
        case "events.pull":
            return try await handleEventsPull(request)
        case "schema.list":
            return try handleSchemaList(request)
        default:
            throw XPCError(
                code: "schema.unknown_command",
                message: "Unknown command: \(request.command)",
                field: "command",
                got: request.command
            )
        }
    }

    // MARK: - Briefing Handlers

    private func handleBriefingPut(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(BriefingPutParams.self, from: request)
        try SchemaValidator.validateBriefingPut(date: params.date, generatedBy: params.generatedBy)

        let context = ModelContext(container)
        let date = params.date
        let descriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate { $0.date == date }
        )
        let existing = try context.fetch(descriptor).first

        let now = Date()
        let publishedAt: Date?

        if let briefing = existing {
            briefing.generatedAt = now
            briefing.generatedBy = params.generatedBy
            if params.published && briefing.publishedAt == nil {
                briefing.publishedAt = now
            }
            publishedAt = briefing.publishedAt
        } else {
            let briefing = BriefingModel(
                date: params.date,
                generatedAt: now,
                generatedBy: params.generatedBy,
                publishedAt: params.published ? now : nil
            )
            context.insert(briefing)
            publishedAt = briefing.publishedAt
        }

        try context.save()

        let result = BriefingPutResult(date: params.date, generatedAt: now, publishedAt: publishedAt)
        return try JSONEncoder.xpc.encode(result)
    }

    private func handleBriefingPublish(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(BriefingPublishParams.self, from: request)
        try SchemaValidator.validateBriefingPublish(date: params.date)
        let dateValue = params.date

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate { $0.date == dateValue }
        )
        guard let briefing = try context.fetch(descriptor).first else {
            throw XPCError(
                code: "briefing.not_found",
                message: "No briefing found for date '\(params.date)'"
            )
        }

        let now = Date()
        if briefing.publishedAt == nil {
            briefing.publishedAt = now
        }
        try context.save()

        let result = BriefingPublishResult(
            date: params.date,
            publishedAt: briefing.publishedAt ?? now
        )
        return try JSONEncoder.xpc.encode(result)
    }

    private func handleBriefingGet(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(BriefingGetParams.self, from: request)
        try SchemaValidator.validateBriefingGet(date: params.date)
        let dateValue = params.date

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate { $0.date == dateValue }
        )
        guard let model = try context.fetch(descriptor).first else {
            throw XPCError(
                code: "briefing.not_found",
                message: "No briefing found for date '\(params.date)'"
            )
        }

        let briefing = Briefing(
            date: model.date,
            generatedAt: model.generatedAt,
            generatedBy: model.generatedBy,
            containers: model.containers
                .sorted { $0.order < $1.order }
                .map { containerModel in
                    Container(
                        id: containerModel.id,
                        title: containerModel.title,
                        subtitle: containerModel.subtitle,
                        order: containerModel.order,
                        layout: containerModel.layout,
                        style: containerModel.style,
                        cards: containerModel.cards.map { cardModel in
                            Card(
                                id: cardModel.id,
                                type: cardModel.type,
                                size: cardModel.size,
                                style: cardModel.style,
                                payload: cardModel.payloadJSON
                            )
                        }
                    )
                }
        )

        let result = BriefingGetResult(briefing: briefing)
        return try JSONEncoder.xpc.encode(result)
    }

    // MARK: - Container Handlers

    private func handleContainerPut(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(ContainerPutParams.self, from: request)
        try SchemaValidator.validateContainerPut(
            id: params.id,
            briefingDate: params.briefingDate,
            title: params.title,
            order: params.order,
            layout: params.layout.rawValue,
            style: params.style.rawValue
        )

        let context = ModelContext(container)

        // Verify parent briefing exists
        let briefingDate = params.briefingDate
        let briefingDescriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate { $0.date == briefingDate }
        )
        guard let briefing = try context.fetch(briefingDescriptor).first else {
            throw XPCError(
                code: "briefing.not_found",
                message: "No briefing found for date '\(params.briefingDate)'"
            )
        }

        // Upsert by (briefing_date, id): only treat an existing container as a
        // match when it already belongs to the requested briefing. A same-id
        // container under a different briefing must not be silently moved.
        let containerId = params.id
        let containerDescriptor = FetchDescriptor<ContainerModel>(
            predicate: #Predicate { $0.id == containerId }
        )
        let existing = try context.fetch(containerDescriptor).first
        if let existing, existing.briefing?.date != params.briefingDate {
            throw XPCError(
                code: "internal.unexpected",
                message: "Container id already exists under a different briefing",
                field: "id",
                got: params.id
            )
        }
        let now = Date()
        let wasCreated: Bool

        if let containerModel = existing {
            containerModel.title = params.title
            containerModel.subtitle = params.subtitle
            containerModel.order = params.order
            containerModel.layout = params.layout
            containerModel.style = params.style
            containerModel.briefing = briefing
            wasCreated = false
        } else {
            let containerModel = ContainerModel(
                id: params.id,
                title: params.title,
                subtitle: params.subtitle,
                order: params.order,
                layout: params.layout,
                style: params.style
            )
            containerModel.briefing = briefing
            context.insert(containerModel)
            wasCreated = true
        }

        try context.save()

        let result = ContainerPutResult(id: params.id, updatedAt: now, wasCreated: wasCreated)
        return try JSONEncoder.xpc.encode(result)
    }

    private func handleContainerDelete(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(ContainerDeleteParams.self, from: request)
        try SchemaValidator.validateContainerDelete(id: params.id)

        let context = ModelContext(container)
        let containerId = params.id
        let descriptor = FetchDescriptor<ContainerModel>(
            predicate: #Predicate { $0.id == containerId }
        )
        guard let containerModel = try context.fetch(descriptor).first else {
            throw XPCError(
                code: "container.not_found",
                message: "No container found with id '\(params.id)'"
            )
        }

        context.delete(containerModel)
        try context.save()

        return try JSONEncoder.xpc.encode(ContainerDeleteResult())
    }

    // MARK: - Card Handlers

    private func handleCardPut(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(CardPutParams.self, from: request)
        try SchemaValidator.validateCardPut(
            containerId: params.containerId,
            id: params.id,
            type: params.type.rawValue,
            size: params.size.rawValue,
            style: params.style.rawValue,
            payload: params.payload
        )

        let context = ModelContext(container)

        // Verify parent container exists
        let containerId = params.containerId
        let containerDescriptor = FetchDescriptor<ContainerModel>(
            predicate: #Predicate { $0.id == containerId }
        )
        guard let parentContainer = try context.fetch(containerDescriptor).first else {
            throw XPCError(
                code: "container.not_found",
                message: "No container found with id '\(params.containerId)'"
            )
        }

        // Upsert by (container_id, id): only treat an existing card as a match
        // when it already belongs to the requested container. A same-id card
        // under a different container must not be silently moved.
        let cardId = params.id
        let cardDescriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.id == cardId }
        )
        let existing = try context.fetch(cardDescriptor).first
        if let existing, existing.container?.id != params.containerId {
            throw XPCError(
                code: "internal.unexpected",
                message: "Card id already exists under a different container",
                field: "id",
                got: params.id
            )
        }
        let now = Date()
        let wasCreated: Bool

        if let cardModel = existing {
            cardModel.typeRaw = params.type.rawValue
            cardModel.sizeRaw = params.size.rawValue
            cardModel.styleRaw = params.style.rawValue
            cardModel.payloadJSON = params.payload
            cardModel.container = parentContainer
            wasCreated = false
        } else {
            let cardModel = CardModel(
                id: params.id,
                type: params.type,
                size: params.size,
                style: params.style,
                payloadJSON: params.payload
            )
            cardModel.container = parentContainer
            context.insert(cardModel)
            wasCreated = true
        }

        try context.save()

        let result = CardPutResult(id: params.id, updatedAt: now, wasCreated: wasCreated)
        return try JSONEncoder.xpc.encode(result)
    }

    private func handleCardDelete(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(CardDeleteParams.self, from: request)
        try SchemaValidator.validateCardDelete(id: params.id)

        let context = ModelContext(container)
        let cardId = params.id
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.id == cardId }
        )
        guard let cardModel = try context.fetch(descriptor).first else {
            throw XPCError(
                code: "card.not_found",
                message: "No card found with id '\(params.id)'"
            )
        }

        context.delete(cardModel)
        try context.save()

        return try JSONEncoder.xpc.encode(CardDeleteResult())
    }

    // MARK: - Events Handler

    private func handleEventsPull(_ request: XPCRequest) async throws -> Data {
        let params = try decodeParams(EventsPullParams.self, from: request)
        try SchemaValidator.validateEventsPull(cardId: params.cardId)

        let context = ModelContext(container)
        let since = params.since
        let until = params.until
        let filterCardId = params.cardId
        let filterAction = params.action?.rawValue

        let predicate: Predicate<UserEventModel>
        if let until, let filterCardId, let filterAction {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.timestamp < until &&
                event.cardId == filterCardId &&
                event.actionRaw == filterAction
            }
        } else if let until, let filterCardId {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.timestamp < until &&
                event.cardId == filterCardId
            }
        } else if let until, let filterAction {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.timestamp < until &&
                event.actionRaw == filterAction
            }
        } else if let filterCardId, let filterAction {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.cardId == filterCardId &&
                event.actionRaw == filterAction
            }
        } else if let until {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.timestamp < until
            }
        } else if let filterCardId {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.cardId == filterCardId
            }
        } else if let filterAction {
            predicate = #Predicate { event in
                event.timestamp >= since &&
                event.actionRaw == filterAction
            }
        } else {
            predicate = #Predicate { event in
                event.timestamp >= since
            }
        }

        let descriptor = FetchDescriptor<UserEventModel>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .forward),
                SortDescriptor(\.device, order: .forward),
                SortDescriptor(\.cardId, order: .forward)
            ]
        )

        let fetchedEvents = try context.fetch(descriptor)

        let events = fetchedEvents.map { model in
            UserEvent(
                id: model.id,
                timestamp: model.timestamp,
                device: model.device,
                cardId: model.cardId,
                action: model.action ?? .done
            )
        }

        let result = EventsPullResult(events: events, count: events.count)
        return try JSONEncoder.xpc.encode(result)
    }

    // MARK: - Schema Handler

    private func handleSchemaList(_ request: XPCRequest) throws -> Data {
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
        return try JSONEncoder.xpc.encode(result)
    }

    // MARK: - Payload Schema Descriptions

    private static let payloadSchemas: [String: String] = {
        var schemas: [String: String] = [:]
        schemas[CardType.metric.rawValue] = """
        {"type":"object","required":["items"],"properties":{"items":{"type":"array","minItems":1,"items":{"type":"object","required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"number"},"unit":{"type":"string"},"trend":{"type":"string","enum":["up","down","flat"]}}}}}}
        """
        schemas[CardType.insight.rawValue] = """
        {"type":"object","required":["title","body"],"properties":{"title":{"type":"string","minLength":1},"body":{"type":"string","minLength":1},"citations":{"type":"array","items":{"type":"object","required":["label","url"],"properties":{"label":{"type":"string"},"url":{"type":"string"}}}}}}
        """
        schemas[CardType.agentSummary.rawValue] = """
        {"type":"object","required":["agentName","completed"],"properties":{"agentName":{"type":"string","minLength":1},"completed":{"type":"array","minItems":1,"items":{"type":"object","required":["title"],"properties":{"title":{"type":"string"},"ref":{"type":"string"}}}},"stats":{"type":"array","items":{"type":"object","required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"number"}}}}}}
        """
        schemas[CardType.todoList.rawValue] = """
        {"type":"object","required":["items"],"properties":{"items":{"type":"array","minItems":1,"items":{"type":"object","required":["title"],"properties":{"title":{"type":"string"},"priority":{"type":"string","enum":["low","medium","high"]},"due":{"type":"string","format":"date-time"},"ref":{"type":"string"}}}}}}
        """
        schemas[CardType.trending.rawValue] = """
        {"type":"object","required":["topic","items"],"properties":{"topic":{"type":"string","minLength":1},"items":{"type":"array","minItems":1,"items":{"type":"object","required":["title","url"],"properties":{"title":{"type":"string"},"url":{"type":"string"},"score":{"type":"number"}}}}}}
        """
        schemas[CardType.digest.rawValue] = """
        {"type":"object","required":["title","body"],"properties":{"title":{"type":"string","minLength":1},"body":{"type":"string","minLength":1},"sections":{"type":"array","items":{"type":"object","required":["heading","paragraphs"],"properties":{"heading":{"type":"string"},"paragraphs":{"type":"array","items":{"type":"string"}}}}}}}
        """
        schemas[CardType.sectionHeader.rawValue] = """
        {"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1},"subtitle":{"type":"string"}}}
        """
        return schemas
    }()

    // MARK: - Helpers

    private func decodeParams<T: Decodable>(_ type: T.Type, from request: XPCRequest) throws -> T {
        do {
            return try JSONDecoder.xpc.decode(type, from: request.params)
        } catch {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "Failed to decode params for '\(request.command)'",
                cause: error.localizedDescription
            )
        }
    }

    private static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }()
}

// MARK: - JSON Coder Configuration

private extension JSONEncoder {
    static let xpc: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let xpc: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
#endif
