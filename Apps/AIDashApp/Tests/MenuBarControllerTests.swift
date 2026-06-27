#if os(macOS)
import Testing
import Foundation
import AppKit
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

// MARK: - Layout-recursion regression (MY-1034)
//
// The original menu-bar icon was an SF Symbol installed on a
// `NSStatusItem.variableLength` host without an explicit size or template
// flag. On macOS 26 that combination made AppKit re-enter
// `-layoutSubtreeIfNeeded` during the initial layout pass, producing the
// `_NSDetectedLayoutRecursion` warning that MY-1017 was supposed to fix.
// This test pins the contract that prevents that recursion: a fixed-length
// status item plus a template image whose `size` is set before being
// handed to the button.
@MainActor
@Test func menuBarStatusItemUsesFixedLengthAndSizedTemplateIcon() async throws {
    let controller = MenuBarController()
    defer {
        if let item = controller.statusItemForTesting {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    let item = try #require(controller.statusItemForTesting)
    #expect(item.length == NSStatusItem.squareLength)

    let icon = try #require(item.button?.image)
    #expect(icon.isTemplate)
    #expect(icon.size == NSSize(width: 18, height: 18))
    #expect(icon.accessibilityDescription == MenuBarController.appName)
}
#endif
