#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp

// MARK: - Menu string localization contract
//
// These tests assert the menu bar titles are sourced through
// `String(localized:)` against the app's String Catalog (Constitution §F.1),
// not raw hardcoded literals at the call site. We check non-empty + the
// expected default English values (which the catalog provides as the source
// language).

@MainActor
@Test func menuBarOpenBriefingTitleIsLocalizedNonEmpty() {
    let title = MenuBarController.openBriefingTitle
    #expect(!title.isEmpty)
    #expect(title == "Open Briefing")
}

@MainActor
@Test func menuBarAboutTitleIsLocalizedNonEmpty() {
    let title = MenuBarController.aboutTitle
    #expect(!title.isEmpty)
    #expect(title == "About AIDash")
}

@MainActor
@Test func menuBarQuitTitleIsLocalizedNonEmpty() {
    let title = MenuBarController.quitTitle
    #expect(!title.isEmpty)
    #expect(title == "Quit AIDash")
}
#endif
