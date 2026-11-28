import SwiftUI

/// Demo dashboard proving the design language: independent KPI cards in a grid,
/// single-hue data-viz next to monochrome P0 numbers, and exception-only status pills.
/// Lives in DesignKit so it's reusable in previews and the snapshot pipeline.
public struct DashboardView: View {
    private let theme = Theme.system
    private let trend: [Double] = [12, 18, 15, 24, 21, 30, 28, 36]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Overview")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    Card {
                        Metric(value: "$48,250", label: "Balance", delta: ("12.4%", true))
                        Sparkline(data: trend, color: theme.primary.primary)
                    }
                    Card {
                        Metric(value: "1,284", label: "Active users", delta: ("3.1%", true))
                        Sparkline(data: trend.reversed(), color: theme.primary.primary.opacity(0.75))
                    }
                    Card {
                        Metric(value: "$3,910", label: "Spend", delta: ("1.8%", false))
                        Sparkline(data: [8, 14, 10, 20, 16, 12, 18, 9], color: theme.neutrals.text2)
                    }
                    Card {
                        HStack {
                            Metric(value: "72%", label: "Savings goal")
                            Spacer()
                            RingGauge(value: 0.72)
                        }
                    }
                }

                Card {
                    SectionHeader("Recent activity")
                    ForEach(Self.demoActivityRows, id: \.title) { row in
                        CardInner {
                            StatusPill(row.statusLabel, tone: row.pillTone)
                            Text(row.title)
                                .font(TypeScale.body)
                                .foregroundStyle(theme.neutrals.text1)
                            Spacer()
                            Text(row.value)
                                .font(TypeScale.num)
                                .foregroundStyle(theme.neutrals.text1)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: Space.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(theme.neutrals.bg)
    }

    struct ActivityRow: Sendable, Equatable {
        let title: String
        let value: String
        let statusLabel: String
        let pillTone: PillTone
    }

    static var demoActivityRows: [ActivityRow] {
        [
            ActivityRow(title: "Payment received", value: "+$1,200", statusLabel: "settled", pillTone: .neutral),
            ActivityRow(title: "Subscription renewed", value: "-$29", statusLabel: "routine", pillTone: .neutral),
            ActivityRow(title: "Card declined", value: "$0", statusLabel: "blocked", pillTone: .danger),
            ActivityRow(title: "Review pending", value: "—", statusLabel: "attention", pillTone: .warning)
        ]
    }
}

#Preview("Dashboard") {
    DashboardView()
        .frame(width: 720, height: 640)
}
