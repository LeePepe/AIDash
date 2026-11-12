#if os(macOS)
import SwiftUI
import DesignKit

/// Breakpoints use the first layout proposal, including in a hostless ImageRenderer.
/// Flexible grids cannot be used as width probes: their minimum width is always zero.
struct DashboardResponsiveGrid: Layout {
    var wideColumns = 4
    var compactColumns = 2
    var spacing = Space.gap

    private func columns(_ width: CGFloat) -> Int {
        width >= 960 ? wideColumns : (width >= 640 ? compactColumns : 1)
    }

    private struct Measurement {
        let width: CGFloat
        let columns: Int
        let cellWidth: CGFloat
        let heights: [CGFloat]
    }

    private func geometry(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Measurement {
        let width = proposal.width ?? 640
        let count = columns(width)
        let cellWidth = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        let heights = stride(from: 0, to: subviews.count, by: count).map { start in
            (start..<min(start + count, subviews.count)).map {
                subviews[$0].sizeThatFits(.init(width: cellWidth, height: nil)).height
            }.max() ?? 0
        }
        return .init(width: width, columns: count, cellWidth: cellWidth, heights: heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = geometry(proposal, subviews)
        return .init(width: measured.width, height: measured.heights.reduce(0, +) + spacing * CGFloat(max(0, measured.heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = geometry(.init(width: bounds.width, height: nil), subviews)
        let count = measured.columns
        let width = measured.cellWidth
        let heights = measured.heights
        var y = bounds.minY
        for row in heights.indices {
            for column in 0..<count {
                let index = row * count + column
                guard index < subviews.count else { continue }
                subviews[index].place(at: .init(x: bounds.minX + CGFloat(column) * (width + spacing), y: y),
                                     anchor: .topLeading, proposal: .init(width: width, height: heights[row]))
            }
            y += heights[row] + spacing
        }
    }
}
#endif
