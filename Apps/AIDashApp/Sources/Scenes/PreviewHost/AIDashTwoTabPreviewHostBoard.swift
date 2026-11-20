#if os(macOS)
import SwiftUI

@MainActor
public struct AIDashTwoTabPreviewHostBoard: View {
    @State private var activeTab: DashboardWorkspaceSection = .overview
    @State private var expandAll = false
    @State private var speed: PreviewSpeedMultiplier = .normal
    @State private var darkAppearance = true
    @StateObject private var receiptWriter: PreviewSelectionReceiptWriter
    private let data: AIDashPreviewSampleData

    public init(data: AIDashPreviewSampleData? = nil, receiptPath: URL? = nil) {
        self.data = data ?? AIDashPreviewSampleData.liveOrFallback()
        _receiptWriter = StateObject(wrappedValue: PreviewSelectionReceiptWriter(path: receiptPath))
    }

    private var descriptors: [PreviewVariantDescriptor] {
        activeTab == .overview
            ? Tab1QuotasAndAgentEfficiencySections.descriptors
            : Tab2SkillsArsenalInspectorSections.descriptors
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(minimum: 420), spacing: 14), GridItem(.flexible(minimum: 420), spacing: 14)], spacing: 14) {
                    ForEach(descriptors) { descriptor in
                        variantCard(descriptor)
                    }
                }
                .padding(18)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .preferredColorScheme(darkAppearance ? .dark : .light)
        .frame(minWidth: 1180, minHeight: 760)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AIDash PreviewHost").font(.title3.weight(.bold))
                    Text("Native 120Hz · 2 × 10 Observatory Gallery").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                selectionPill
                Button { expandAll.toggle() } label: { Label(expandAll ? "Collapse All" : "Toggle All", systemImage: expandAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical") }.buttonStyle(.bordered).controlSize(.small)
                Picker("Spring speed", selection: $speed) { ForEach(PreviewSpeedMultiplier.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).frame(width: 210)
                Button { darkAppearance.toggle() } label: { Label(darkAppearance ? "Dark" : "Light", systemImage: darkAppearance ? "moon.fill" : "sun.max.fill") }.buttonStyle(.bordered).controlSize(.small)
            }
            HStack(spacing: 8) {
                tabButton(.overview, title: "Tab 1 · Quotas & Agent Efficiency", count: Tab1QuotasAndAgentEfficiencySections.descriptors.count)
                tabButton(.agentEfficiency, title: "Tab 2 · Skills Arsenal Inspector", count: Tab2SkillsArsenalInspectorSections.descriptors.count)
                Spacer()
                Text("Receipt: \(receiptWriter.path.path)").font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var selectionPill: some View {
        let selected = receiptWriter.receipt.selectedVariantID.isEmpty ? 0 : 1
        return Text("Selected \(selected) · Starred ★ \(receiptWriter.receipt.starredVariantIDs.count)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.13), in: Capsule())
    }

    private func tabButton(_ tab: DashboardWorkspaceSection, title: String, count: Int) -> some View {
        Button { withAnimation(speed.spring()) { activeTab = tab } } label: {
            HStack(spacing: 7) { Image(systemName: tab.symbolName); Text(title); Text("V01–V\(String(format: "%02d", count))").font(.caption2.monospacedDigit()).opacity(0.7) }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(activeTab == tab ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func variantCard(_ descriptor: PreviewVariantDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(descriptor.badgeCode).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.tint).padding(.horizontal, 7).padding(.vertical, 4).background(Color.accentColor.opacity(0.14), in: Capsule())
                Text(descriptor.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 4)
                Text(descriptor.topologySignature.split(separator: ":", maxSplits: 1).last.map(String.init) ?? descriptor.topologySignature).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 7) {
                Button { receiptWriter.select(descriptor.id) } label: { Text(receiptWriter.receipt.selectedVariantID == descriptor.id ? "SELECTED ✓" : "SELECT") }.buttonStyle(.borderedProminent).controlSize(.small)
                Button { receiptWriter.toggleStar(descriptor.id) } label: { Label(receiptWriter.receipt.starredVariantIDs.contains(descriptor.id) ? "STARRED" : "STAR", systemImage: receiptWriter.receipt.starredVariantIDs.contains(descriptor.id) ? "star.fill" : "star") }.buttonStyle(.bordered).controlSize(.small)
                TextField("NOTES", text: Binding(get: { receiptWriter.receipt.notesByVariant[descriptor.id] ?? "" }, set: { receiptWriter.setNote($0, for: descriptor.id) }))
                    .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 220)
            }
            sectionView(for: descriptor)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(darkAppearance ? 0.18 : 0.06), radius: 8, y: 3)
    }

    @ViewBuilder
    private func sectionView(for descriptor: PreviewVariantDescriptor) -> some View {
        if descriptor.tab == .overview {
            Tab1QuotasAndAgentEfficiencySections.view(for: descriptor, data: data, globalExpandAll: expandAll, speed: speed)
        } else {
            Tab2SkillsArsenalInspectorSections.view(for: descriptor, data: data, globalExpandAll: expandAll, speed: speed)
        }
    }
}

#Preview("2 × 10 PreviewHost") {
    AIDashTwoTabPreviewHostBoard(data: .fallback())
}
#endif
