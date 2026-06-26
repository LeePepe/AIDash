import Testing
import Foundation
@testable import AIDashApp

@Test func briefingStorageUnavailableTitleIsLocalized() async throws {
    let value = String(
        localized: "briefing.storage_unavailable.title",
        defaultValue: "iCloud unavailable",
        bundle: .main
    )
    #expect(!value.isEmpty)
    #expect(value == "iCloud unavailable")
}
