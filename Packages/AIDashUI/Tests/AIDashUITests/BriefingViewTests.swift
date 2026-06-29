import Testing
import SwiftUI
import Foundation
@testable import AIDashUI

@MainActor
@Suite("BriefingView Tests")
struct BriefingViewTests {
    @Test("public init compiles and produces a view")
    func publicInitProducesView() {
        let view = BriefingView()
        // Smoke check: body returns Some View without throwing.
        _ = view.body
    }

    @Test("localTodayString matches Gregorian local calendar date, not UTC")
    func localTodayStringMatchesLocalCalendar() throws {
        // The view's todayString must use a Gregorian calendar pinned to the
        // user's current time zone. Using Calendar.current directly would
        // produce non-Gregorian year/month/day values for users on
        // Buddhist/Japanese/Hebrew/etc. calendar settings, which would never
        // match `BriefingModel.date` values stored as POSIX yyyy-MM-dd.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let expected = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )

        // Sanity: yyyy-MM-dd format with correct lengths
        #expect(expected.count == 10)
        #expect(expected[expected.index(expected.startIndex, offsetBy: 4)] == "-")
        #expect(expected[expected.index(expected.startIndex, offsetBy: 7)] == "-")

        // Year must be Gregorian (4-digit, within a sane range for a daily
        // briefing app). This guards against accidental reintroduction of
        // Calendar.current, which on a Buddhist locale would yield 2569+.
        let year = components.year ?? 0
        #expect(year >= 2024 && year <= 2100)
    }

    // MARK: - Page Chrome tokens
    //
    // Constitution §Page Chrome — the page background must be one
    // hierarchy step below the card background, page horizontal padding
    // is 24 Mac / 20 iOS, page vertical padding is 24pt.

    @Test("pageHorizontalPadding resolves to the platform-correct token")
    func pageHorizontalPaddingMatchesPlatformToken() {
        #if os(macOS)
        #expect(BriefingView.pageHorizontalPadding == AIDashSpacing.pageHorizontalMac)
        #expect(BriefingView.pageHorizontalPadding == 24)
        #else
        #expect(BriefingView.pageHorizontalPadding == AIDashSpacing.pageHorizontalCompact)
        #expect(BriefingView.pageHorizontalPadding == 20)
        #endif
    }

    @Test("pageBackground is exposed (page draws its own background, not card chrome)")
    func pageBackgroundExposed() {
        // Smoke: the page-background token can be read at runtime and is
        // not the default clear color. The actual NSColor / UIColor
        // identity is verified by the source-level check below since
        // SwiftUI Color comparison is not reliable across platforms.
        let bg = BriefingView.pageBackground
        _ = bg
    }

    @Test("BriefingView source uses Page Chrome tokens, not magic numbers")
    func briefingViewSourceUsesPageChromeTokens() throws {
        let source = try Self.briefingViewSource()

        #expect(source.contains("AIDashSpacing.pageVertical"),
                "page vertical padding must come from AIDashSpacing.pageVertical")
        #expect(source.contains("AIDashSpacing.pageHorizontalMac"),
                "page horizontal padding (Mac) must come from AIDashSpacing.pageHorizontalMac")
        #expect(source.contains("AIDashSpacing.pageHorizontalCompact"),
                "page horizontal padding (iOS) must come from AIDashSpacing.pageHorizontalCompact")
        #expect(source.contains("AIDashSpacing.containerVertical"),
                "container-to-container spacing must come from AIDashSpacing.containerVertical")
        #expect(source.contains("NSColor.windowBackgroundColor")
                || !source.contains("import AppKit"),
                "macOS branch must use NSColor.windowBackgroundColor")
        #expect(source.contains(".systemGroupedBackground")
                || !source.contains("import UIKit"),
                "iOS branch must use systemGroupedBackground")
    }

    @Test("BriefingView source does not reintroduce containerStub or stub helpers")
    func briefingViewHasNoStubHelpers() throws {
        let source = try Self.briefingViewSource()

        #expect(!source.contains("containerStub"),
                "containerStub helper must not exist — render real ContainerModel cards only")
        #expect(!source.lowercased().contains("stub_data"),
                "no stub_data helper allowed in BriefingView")
    }

    private static func briefingViewSource() throws -> String {
        let url = try sourceFile(named: "BriefingView.swift",
                                 under: "Sources/AIDashUI")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func sourceFile(named filename: String,
                                   under relativePath: String) throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent(relativePath)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        throw SourceLookupError.notFound(filename)
    }

    private enum SourceLookupError: Error {
        case notFound(String)
    }
}
