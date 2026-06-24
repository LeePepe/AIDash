import Testing
import Foundation
@testable import AIDashCore

@Test func briefingModelInit() async throws {
    let now = Date()
    let briefing = BriefingModel(date: "2026-06-23", generatedAt: now, generatedBy: "test")

    #expect(briefing.date == "2026-06-23")
    #expect(briefing.generatedAt == now)
    #expect(briefing.generatedBy == "test")
    #expect(briefing.publishedAt == nil)
    #expect(briefing.containers.isEmpty)
}

@Test func briefingModelInitWithPublishedAt() async throws {
    let now = Date()
    let published = Date(timeIntervalSinceNow: -3600)
    let briefing = BriefingModel(
        date: "2026-06-24",
        generatedAt: now,
        generatedBy: "agent",
        publishedAt: published
    )

    #expect(briefing.date == "2026-06-24")
    #expect(briefing.generatedBy == "agent")
    #expect(briefing.publishedAt == published)
    #expect(briefing.containers.isEmpty)
}

@Test func containerModelInit() async throws {
    let container = ContainerModel(
        id: "C1",
        title: "Overview",
        subtitle: "Daily summary",
        order: 10,
        layout: .grid,
        style: .accent
    )

    #expect(container.id == "C1")
    #expect(container.title == "Overview")
    #expect(container.subtitle == "Daily summary")
    #expect(container.order == 10)
    #expect(container.layout == .grid)
    #expect(container.style == .accent)
    #expect(container.layoutRaw == "grid")
    #expect(container.styleRaw == "accent")
    #expect(container.briefing == nil)
}

@Test func containerModelComputedSetters() async throws {
    let container = ContainerModel(
        id: "C2",
        title: "Tasks",
        subtitle: nil,
        order: 20,
        layout: .auto,
        style: .neutral
    )

    container.layout = .hero
    container.style = .warning

    #expect(container.layoutRaw == "hero")
    #expect(container.styleRaw == "warning")
    #expect(container.layout == .hero)
    #expect(container.style == .warning)
    #expect(container.subtitle == nil)
}
