#if os(macOS)
import SwiftUI

@MainActor
public struct PreviewSelectionSummaryPill: View {
    private let receiptWriter: PreviewSelectionReceiptWriter
    @State private var selectedCount: Int
    @State private var starredCount: Int
    @State private var observerToken: UUID?

    public init(receiptWriter: PreviewSelectionReceiptWriter) {
        self.receiptWriter = receiptWriter
        let counts = receiptWriter.summaryCounts
        _selectedCount = State(initialValue: counts.selected)
        _starredCount = State(initialValue: counts.starred)
    }

    public var body: some View {
        Text("已选 \(selectedCount) · 收藏 ★ \(starredCount)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.13), in: Capsule())
            .onAppear {
                let counts = receiptWriter.summaryCounts
                selectedCount = counts.selected
                starredCount = counts.starred
                if observerToken == nil {
                    observerToken = receiptWriter.observeSummary { selected, starred in
                        selectedCount = selected
                        starredCount = starred
                    }
                }
            }
            .onDisappear {
                if let token = observerToken {
                    receiptWriter.removeSummaryObserver(token)
                    observerToken = nil
                }
            }
    }
}

@MainActor
public struct PreviewVariantFeedbackBar: View {
    public let variantID: String
    private let receiptWriter: PreviewSelectionReceiptWriter
    @State private var isSelected: Bool
    @State private var isStarred: Bool
    @State private var noteText: String
    @State private var selectionObserverToken: UUID?

    public init(variantID: String, receiptWriter: PreviewSelectionReceiptWriter) {
        self.variantID = variantID
        self.receiptWriter = receiptWriter
        let current = receiptWriter.receipt
        _isSelected = State(initialValue: current.selectedVariantID == variantID)
        _isStarred = State(initialValue: current.starredVariantIDs.contains(variantID))
        _noteText = State(initialValue: current.notesByVariant[variantID] ?? "")
    }

    public var body: some View {
        HStack(spacing: 7) {
            Button {
                let updatedID = receiptWriter.select(variantID)
                isSelected = (updatedID == variantID)
            } label: {
                Text(isSelected ? "SELECTED ✓" : "SELECT")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                isStarred = receiptWriter.toggleStar(variantID)
            } label: {
                Label(isStarred ? "STARRED ★" : "STAR ★", systemImage: isStarred ? "star.fill" : "star")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            TextField("NOTES", text: $noteText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(maxWidth: 220)
                .onChange(of: noteText) { _, newValue in
                    receiptWriter.setNote(newValue, for: variantID)
                }
        }
        .onAppear {
            let current = receiptWriter.receipt
            isSelected = (current.selectedVariantID == variantID)
            isStarred = current.starredVariantIDs.contains(variantID)
            noteText = current.notesByVariant[variantID] ?? ""
            if selectionObserverToken == nil {
                selectionObserverToken = receiptWriter.observeSelection { selectedID in
                    let shouldSelect = (selectedID == variantID)
                    if isSelected != shouldSelect {
                        isSelected = shouldSelect
                    }
                }
            }
        }
        .onDisappear {
            if let token = selectionObserverToken {
                receiptWriter.removeSelectionObserver(token)
                selectionObserverToken = nil
            }
        }
    }
}

@MainActor
public struct AIDashTwoTabPreviewHostBoard: View {
    @State private var activeTab: DashboardWorkspaceSection = .overview
    @State private var expandAll = false
    @State private var speed: PreviewSpeedMultiplier = .normal
    @State private var darkAppearance = true
    @State private var receiptWriter: PreviewSelectionReceiptWriter
    private let data: AIDashPreviewSampleData

    public init(data: AIDashPreviewSampleData? = nil, receiptPath: URL? = nil) {
        self.data = data ?? AIDashPreviewSampleData.liveOrFallback()
        _receiptWriter = State(initialValue: PreviewSelectionReceiptWriter(path: receiptPath))
    }

    private var descriptors: [PreviewVariantDescriptor] {
        switch activeTab {
        case .overview:
            return Tab1QuotasAndAgentEfficiencySections.descriptors
        case .goalWorkStream:
            return Tab3GoalWorkStreamSections.descriptors
        default:
            return Tab2SkillsArsenalInspectorSections.descriptors
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 420), spacing: 14),
                        GridItem(.flexible(minimum: 420), spacing: 14)
                    ],
                    spacing: 14
                ) {
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
                    Text("AIDash PreviewHost · 三段式工作台与趋势探索画廊").font(.title3.weight(.bold))
                    Text("Native 120Hz · 总览与进化 · Goal 与工作流 (2+1+1) · Skills 武器库").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PreviewSelectionSummaryPill(receiptWriter: receiptWriter)
                Button { expandAll.toggle() } label: {
                    Label(
                        expandAll ? "收起全部抽屉" : "展开全部抽屉",
                        systemImage: expandAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Picker("动画速度", selection: $speed) {
                    ForEach(PreviewSpeedMultiplier.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                Button { darkAppearance.toggle() } label: {
                    Label(darkAppearance ? "深色" : "浅色", systemImage: darkAppearance ? "moon.fill" : "sun.max.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            HStack(spacing: 8) {
                tabButton(
                    .overview,
                    title: "总览与进化",
                    count: Tab1QuotasAndAgentEfficiencySections.descriptors.count
                )
                tabButton(
                    .goalWorkStream,
                    title: "Goal 与工作流 (2+1+1)",
                    count: Tab3GoalWorkStreamSections.descriptors.count
                )
                tabButton(
                    .agentEfficiency,
                    title: "Skills 武器库",
                    count: Tab2SkillsArsenalInspectorSections.descriptors.count
                )
                Spacer()
                Text("Receipt: \(receiptWriter.path.lastPathComponent)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabButton(_ tab: DashboardWorkspaceSection, title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: tab.symbolName)
            Text(title)
            Text("V01–V\(String(format: "%02d", count))").font(.caption2.monospacedDigit()).opacity(0.75)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            activeTab == tab ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(speed.spring()) { activeTab = tab }
        }
    }

    @ViewBuilder
    private func variantCard(_ descriptor: PreviewVariantDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(descriptor.badgeCode)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                Text(descriptor.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 4)
                Text(descriptor.topologySignature.split(separator: ":", maxSplits: 1).last.map(String.init) ?? descriptor.topologySignature)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            PreviewVariantFeedbackBar(variantID: descriptor.id, receiptWriter: receiptWriter)
            sectionView(for: descriptor)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(darkAppearance ? 0.18 : 0.06), radius: 8, y: 3)
    }

    @ViewBuilder
    private func sectionView(for descriptor: PreviewVariantDescriptor) -> some View {
        switch descriptor.tab {
        case .overview:
            Tab1QuotasAndAgentEfficiencySections.view(for: descriptor, data: data, globalExpandAll: expandAll, speed: speed)
        case .goalWorkStream:
            Tab3GoalWorkStreamSections.view(for: descriptor, data: data, globalExpandAll: expandAll, speed: speed)
        default:
            Tab2SkillsArsenalInspectorSections.view(for: descriptor, data: data, globalExpandAll: expandAll, speed: speed)
        }
    }
}

#Preview("3-Section PreviewHost") {
    AIDashTwoTabPreviewHostBoard(data: .fallback())
}
#endif
