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
