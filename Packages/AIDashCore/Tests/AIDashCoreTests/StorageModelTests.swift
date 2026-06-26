import Testing
import Foundation
import SwiftData
@testable import AIDashCore

/// Storage-mirror tests for CloudKit-compatible SwiftData @Model classes.
///
/// These exercise:
/// 1. Defaults: each scalar attribute is either optional or has a default,
///    so a CloudKit-backed container can boot without `Store failed to load`.
/// 2. Optional to-many relationships: `BriefingModel.containers` and
///    `ContainerModel.cards` are CloudKit-nullable; business code treats nil
///    as empty array.
/// 3. Idempotent fetch-then-update by logical key — proves the XPC business
///    layer can dedupe by id without `@Attribute(.unique)`.
@Suite("Storage CloudKit-compatible models")
struct StorageModelTests {

    private static func inMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
            configurations: config
        )
    }

    // MARK: - Defaults / optional scalars

    @Test("BriefingModel inserts with default-backed scalars")
    func briefingDefaults() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        let briefing = BriefingModel(
            date: "2026-06-23",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            generatedBy: "agent"
        )
        context.insert(briefing)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BriefingModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.publishedAt == nil)
        #expect(fetched.first?.containers.isEmpty == true)
    }

    @Test("ContainerModel inserts with default-backed scalars")
    func containerDefaults() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        let containerModel = ContainerModel(
            id: "C1", title: "Overview", subtitle: nil, order: 10,
            layout: .auto, style: .neutral
        )
        context.insert(containerModel)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ContainerModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.cards.isEmpty == true)
        #expect(fetched.first?.briefing == nil)
    }

    @Test("CardModel inserts with default-backed scalars")
    func cardDefaults() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        let card = CardModel(
            id: "K1", type: .metric, size: .medium,
            style: .neutral, payloadJSON: Data("{}".utf8)
        )
        context.insert(card)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CardModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.container == nil)
    }

    @Test("UserEventModel inserts with default-backed scalars")
    func userEventDefaults() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        let event = UserEventModel(
            id: "E1", timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            device: "iPhone [DEADBEEF]", cardId: "K1", action: .done
        )
        context.insert(event)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserEventModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.action == .done)
    }

    // MARK: - Optional to-many relationship semantics

    @Test("Briefing.containers returns empty array when relationship is nil")
    func briefingContainersNilTreatedAsEmpty() {
        let briefing = BriefingModel(date: "2026-06-23", generatedAt: .now, generatedBy: "agent")
        briefing.rawContainers = nil
        #expect(briefing.containers.isEmpty)
    }

    @Test("Container.cards returns empty array when relationship is nil")
    func containerCardsNilTreatedAsEmpty() {
        let containerModel = ContainerModel(
            id: "C1", title: "T", subtitle: nil, order: 0,
            layout: .auto, style: .neutral
        )
        containerModel.rawCards = nil
        #expect(containerModel.cards.isEmpty)
    }

    @Test("Briefing.containers round-trips through relationship after insert")
    func briefingContainersRelationship() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        let briefing = BriefingModel(date: "2026-06-25", generatedAt: .now, generatedBy: "agent")
        context.insert(briefing)
        let c1 = ContainerModel(
            id: "C1", title: "First", subtitle: nil, order: 10,
            layout: .auto, style: .neutral
        )
        context.insert(c1)
        c1.briefing = briefing
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BriefingModel>()).first
        #expect(fetched?.containers.count == 1)
        #expect(fetched?.containers.first?.id == "C1")
    }

    // MARK: - Idempotent upsert by logical key (no @Attribute(.unique))

    @Test("Repeated insert by logical key does not create duplicates when XPC-style dedupe is applied")
    func briefingUpsertByDate() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        // First put — insert.
        try upsertBriefing(in: context, date: "2026-06-23", generatedBy: "first")
        // Second put — should fetch existing and update.
        try upsertBriefing(in: context, date: "2026-06-23", generatedBy: "second")

        let fetched = try context.fetch(FetchDescriptor<BriefingModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.generatedBy == "second")
    }

    @Test("Repeated container upsert by id does not duplicate")
    func containerUpsertById() throws {
        let container = try Self.inMemoryContainer()
        let context = ModelContext(container)

        let briefing = BriefingModel(date: "2026-06-23", generatedAt: .now, generatedBy: "agent")
        context.insert(briefing)
        try context.save()

        try upsertContainer(in: context, id: "C1", title: "First", briefing: briefing)
        try upsertContainer(in: context, id: "C1", title: "Renamed", briefing: briefing)

        let fetched = try context.fetch(FetchDescriptor<ContainerModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Renamed")
        #expect(fetched.first?.briefing?.date == "2026-06-23")
    }

    @Test("Repeated card upsert by id does not duplicate and replaces payload")
    func cardUpsertById() throws {
        let modelContainer = try Self.inMemoryContainer()
        let context = ModelContext(modelContainer)

        let briefing = BriefingModel(date: "2026-06-23", generatedAt: .now, generatedBy: "agent")
        context.insert(briefing)
        let parent = ContainerModel(
            id: "C1", title: "T", subtitle: nil, order: 10,
            layout: .auto, style: .neutral
        )
        context.insert(parent)
        parent.briefing = briefing
        try context.save()

        try upsertCard(in: context, id: "K1", payload: Data("{\"v\":1}".utf8), container: parent)
        try upsertCard(in: context, id: "K1", payload: Data("{\"v\":2}".utf8), container: parent)

        let fetched = try context.fetch(FetchDescriptor<CardModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.payloadJSON == Data("{\"v\":2}".utf8))
        #expect(fetched.first?.container?.id == "C1")
    }

    // MARK: - Helpers (mirror the dedupe behavior the XPC handler implements)

    private func upsertBriefing(in context: ModelContext, date: String, generatedBy: String) throws {
        let descriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate { $0.date == date }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.generatedBy = generatedBy
            existing.generatedAt = Date()
        } else {
            let briefing = BriefingModel(date: date, generatedAt: Date(), generatedBy: generatedBy)
            context.insert(briefing)
        }
        try context.save()
    }

    private func upsertContainer(in context: ModelContext, id: String, title: String, briefing: BriefingModel) throws {
        let descriptor = FetchDescriptor<ContainerModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.title = title
            existing.briefing = briefing
        } else {
            let containerModel = ContainerModel(
                id: id, title: title, subtitle: nil, order: 10,
                layout: .auto, style: .neutral
            )
            context.insert(containerModel)
            containerModel.briefing = briefing
        }
        try context.save()
    }

    private func upsertCard(in context: ModelContext, id: String, payload: Data, container parent: ContainerModel) throws {
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.payloadJSON = payload
            existing.container = parent
        } else {
            let card = CardModel(
                id: id, type: .metric, size: .medium,
                style: .neutral, payloadJSON: payload
            )
            context.insert(card)
            card.container = parent
        }
        try context.save()
    }
}
