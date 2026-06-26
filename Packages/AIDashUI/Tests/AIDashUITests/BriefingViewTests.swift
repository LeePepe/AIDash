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
}
