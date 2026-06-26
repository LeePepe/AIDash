#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp

// MARK: - Localization contract tests
//
// These guard Constitution §F.1: every user-visible menu bar string must
// resolve through the String Catalog (`Localizable.xcstrings`) via the
// `String(localized:)` accessor, not a raw literal embedded in source.

@MainActor
@Test func menuBarAppNameIsLocalized() async throws {
    let value = MenuBarController.appName
    #expect(!value.isEmpty)
    #expect(value == "AIDash")
}

@MainActor
@Test func menuBarOpenBriefingIsLocalized() async throws {
    let value = MenuBarController.openBriefingTitle
    #expect(!value.isEmpty)
    #expect(value == "Open Briefing")
}

@MainActor
@Test func menuBarAboutIsLocalized() async throws {
    let value = MenuBarController.aboutTitle
    #expect(!value.isEmpty)
    #expect(value == "About AIDash")
}

@MainActor
@Test func menuBarQuitIsLocalized() async throws {
    let value = MenuBarController.quitTitle
    #expect(!value.isEmpty)
    #expect(value == "Quit AIDash")
}
#endif
