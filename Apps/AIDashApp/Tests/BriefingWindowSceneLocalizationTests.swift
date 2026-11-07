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

@Test func briefingSceneStateCopyDoesNotLeakKeys() {
    let values = [
        String(localized: "briefing.scene.loading.status", defaultValue: "SYNCING", bundle: .main),
        String(localized: "briefing.scene.loading.title", defaultValue: "Loading briefing", bundle: .main),
        String(localized: "briefing.scene.loading.subtitle", defaultValue: "Preparing today’s briefing.", bundle: .main),
        String(localized: "briefing.scene.error.status", defaultValue: "ERROR", bundle: .main),
        String(localized: "briefing.scene.error.title", defaultValue: "Briefing unavailable", bundle: .main),
        String(localized: "briefing.scene.error.subtitle", defaultValue: "Check iCloud and try opening the briefing again.", bundle: .main)
    ]

    for value in values {
        #expect(!value.isEmpty)
    }
}

@Test func desktopWindowMinimumFrameIsMacOSOnly() {
    #expect(AIDashWindowGeometry.requiresDesktopMinFrame(isMacOS: true))
    #expect(!AIDashWindowGeometry.requiresDesktopMinFrame(isMacOS: false))
    #expect(AIDashWindowGeometry.macMinWidth == 880)
    #expect(AIDashWindowGeometry.macMinHeight == 580)
}
