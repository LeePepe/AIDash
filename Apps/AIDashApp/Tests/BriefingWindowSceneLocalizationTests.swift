import Testing
import Foundation
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@Test func briefingStorageUnavailableTitleIsLocalized() async throws {
    let value = String(
        localized: "briefing.storage_unavailable.title",
        defaultValue: "iCloud unavailable",
        bundle: .main
    )
    #expect(!value.isEmpty)
    #expect(value == "iCloud unavailable")
}

@Test func desktopWindowMinimumFrameIsMacOSOnly() {
    #expect(AIDashWindowGeometry.requiresDesktopMinFrame(isMacOS: true))
    #expect(!AIDashWindowGeometry.requiresDesktopMinFrame(isMacOS: false))
    #expect(AIDashWindowGeometry.macMinWidth == 720)
    #expect(AIDashWindowGeometry.macMinHeight == 480)
}
