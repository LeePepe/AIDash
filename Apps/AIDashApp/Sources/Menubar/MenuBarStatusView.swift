#if os(macOS)
import DesignKit
import SwiftUI

@MainActor
public struct MenuBarStatusView: View {
    public let state: MenuBarStatusViewState
    public let onRefresh: () -> Void

    public init(state: MenuBarStatusViewState, onRefresh: @escaping () -> Void = {}) {
        self.state = state
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Group {
            switch state {
            case .loading:
                loadingView
            case let .empty(reason):
                messageView(title: Copy.emptyTitle, message: reason, symbol: "chart.bar.xaxis")
            case let .error(message):
                messageView(title: Copy.errorTitle, message: message, symbol: "exclamationmark.triangle")
            case let .populated(snapshot):
                populatedView(snapshot)
            }
        }
        .frame(width: 340)
        .padding(16)
        .background(theme.neutrals.bg)
        .designTheme(seed: .lime, neutral: .slate)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme {
        Theme(seed: .lime, neutral: .slate, isDark: colorScheme == .dark)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: Copy.title, subtitle: Copy.updating, symbol: "arrow.triangle.2.circlepath")
            ForEach(["cpu", "memory", "storage", "tokens"], id: \.self) { _ in
                skeletonSection
            }
        }
        .accessibilityLabel(Copy.updating)
    }

    private func populatedView(_ snapshot: MenuBarSystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                title: Copy.title,
                subtitle: Copy.updated(snapshot.capturedAt),
                symbol: "checkmark.circle"
            )
            cpuSection(snapshot.cpu)
            memorySection(snapshot.memory)
            storageSection(snapshot.storage)
            tokenSection(snapshot.tokenUsage)
        }
    }

    private func header(title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(theme.primary.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text(.heading))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text(.meta))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.neutrals.border, lineWidth: 1)
        }
    }

    private func cpuSection(_ cpu: CPUStatusSnapshot) -> some View {
        section(title: Copy.cpu) {
            metricRow(
                label: Copy.usage,
                value: percent(cpu.usage),
                detail: Copy.cores(cpu.coreCount),
                symbol: "cpu"
            )
            detailGrid([
                (Copy.user, percent(cpu.user)),
                (Copy.system, percent(cpu.system)),
                (Copy.loadOne, decimal(cpu.loadOneMinute)),
                (Copy.loadFive, decimal(cpu.loadFiveMinutes)),
                (Copy.loadFifteen, decimal(cpu.loadFifteenMinutes))
            ])
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.cpuSummary(cpu))
    }

    private func memorySection(_ memory: MemoryStatusSnapshot) -> some View {
        section(title: Copy.memory) {
            metricRow(
                label: Copy.used,
                value: "\(formatBytes(memory.usedBytes)) / \(formatBytes(memory.totalBytes))",
                detail: percent(memory.usageFraction),
                symbol: "memorychip"
            )
            detailGrid([
                (Copy.free, formatBytes(memory.freeBytes)),
                (Copy.wired, formatBytes(memory.wiredBytes)),
                (Copy.compressed, formatBytes(memory.compressedBytes))
            ])
            statusPill(
                Copy.pressureTitle(memory.pressure),
                fill: pressureColor(memory.pressure),
                text: pressureTextColor(memory.pressure)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.memorySummary(memory))
    }

    private func storageSection(_ storage: StorageStatusSnapshot) -> some View {
        section(title: Copy.storage) {
            volumeRow(storage.systemVolume)
            volumeRow(storage.ssdVolume)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.storageSummary(storage))
    }

    private func tokenSection(_ usage: CLITokenUsageSnapshot) -> some View {
        section(title: Copy.tokens) {
            metricRow(
                label: Copy.active,
                value: formatCount(usage.totalActiveTokens),
                detail: Copy.total(formatCount(usage.grandTotalTokens)),
                symbol: "number"
            )
            ForEach(usage.items) { item in
                tokenRow(item, share: usage.shareFraction(for: item.cli))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.tokenSummary(usage))
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text(.body))
            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(12)
                .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.neutrals.border, lineWidth: 1)
                }
        }
    }

    private func metricRow(label: String, value: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(theme.primary.primary)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.text(.body))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.text(.heading))
            Text(detail)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.text(.body))
        }
        .frame(minHeight: 24)
    }

    private func detailGrid(_ values: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                HStack(spacing: 4) {
                    Text(value.0)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text(.meta))
                    Spacer(minLength: 2)
                    Text(value.1)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.text(.body))
                }
            }
        }
    }

    private func volumeRow(_ volume: StorageVolumeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: volume.isExternalSSD ? "externaldrive" : "internaldrive")
                    .foregroundStyle(volume.isMounted ? theme.success : theme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text(.body))
                    Text(volume.mountPoint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.text(.meta))
                }
                Spacer(minLength: 4)
                if volume.isMounted {
                    Text(percent(volume.usageFraction))
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.text(.heading))
                } else {
                    statusPill(Copy.notMounted, fill: theme.warning, text: theme.warningOnSubtle)
                }
            }
            if volume.isMounted {
                progressBar(value: volume.usageFraction, label: Copy.storage)
                Text("\(formatBytes(volume.usedBytes)) / \(formatBytes(volume.totalBytes)) · \(formatBytes(volume.availableBytes)) \(Copy.available)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.text(.meta))
            }
        }
        .frame(minHeight: 24)
    }

    private func tokenRow(_ item: CLITokenUsageItem, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.isAvailable {
                HStack(spacing: 8) {
                    Text(item.cli.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text(.body))
                    Spacer(minLength: 4)
                    Text(formatCount(item.totalTokens))
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.text(.heading))
                }
                HStack(spacing: 8) {
                    progressBar(value: share, label: item.cli.rawValue)
                    Text("\(Copy.inOut) \(formatCount(item.activeTokens)) · \(Copy.cache) \(formatCount(item.cacheTokens))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.text(.meta))
                }
            } else {
                HStack(spacing: 8) {
                    Text(item.cli.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text(.body))
                    Spacer(minLength: 4)
                    statusPill(Copy.unavailable, fill: theme.danger, text: theme.dangerOnSubtle)
                }
            }
        }
        .frame(minHeight: 24)
    }

    private func progressBar(value: Double, label: String) -> some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.neutrals.inner)
                    .overlay {
                        Capsule()
                            .stroke(theme.neutrals.border, lineWidth: 1)
                    }
                Capsule()
                    .fill(theme.primary.primary)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percent(value))
    }

    private var skeletonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.neutrals.inner)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.neutrals.inner)
                .frame(height: 24)
        }
        .padding(12)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func messageView(title: String, message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: title, subtitle: message, symbol: symbol)
            Button(Copy.refresh, action: onRefresh)
                .buttonStyle(.borderedProminent)
                .tint(theme.primary.primary)
                .frame(minHeight: 28)
                .accessibilityLabel(Copy.refresh)
        }
    }

    private func statusPill(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill.opacity(0.14), in: Capsule())
    }

    private func pressureColor(_ pressure: MemoryPressureLevel) -> Color {
        switch pressure {
        case .normal: return theme.success
        case .warning: return theme.warning
        case .critical: return theme.danger
        }
    }

    private func pressureTextColor(_ pressure: MemoryPressureLevel) -> Color {
        switch pressure {
        case .normal: return theme.successOnSubtle
        case .warning: return theme.warningOnSubtle
        case .critical: return theme.dangerOnSubtle
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func decimal(_ value: Double) -> String { String(format: "%.2f", value) }
    private func formatCount(_ value: UInt64) -> String { value.formatted(.number) }
    private func formatBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    private enum Copy {
        static var title: String { localized("menubar.status.title", "System Status") }
        static var cpu: String { localized("menubar.status.cpu", "CPU") }
        static var memory: String { localized("menubar.status.memory", "Memory") }
        static var storage: String { localized("menubar.status.storage", "Storage") }
        static var tokens: String { localized("menubar.status.tokens", "Agent Token Usage") }
        static var usage: String { localized("menubar.status.usage", "Usage") }
        static var user: String { localized("menubar.status.user", "User") }
        static var system: String { localized("menubar.status.system", "System") }
        static var loadOne: String { localized("menubar.status.load_one", "1m load") }
        static var loadFive: String { localized("menubar.status.load_five", "5m load") }
        static var loadFifteen: String { localized("menubar.status.load_fifteen", "15m load") }
        static var coresFormat: String { localized("menubar.status.cores", "%lld cores") }
        static var used: String { localized("menubar.status.used", "Used") }
        static var free: String { localized("menubar.status.free", "Free") }
        static var wired: String { localized("menubar.status.wired", "Wired") }
        static var compressed: String { localized("menubar.status.compressed", "Compressed") }
        static var active: String { localized("menubar.status.active", "Active") }
        static var totalFormat: String { localized("menubar.status.total", "Total %@") }
        static var inOut: String { localized("menubar.status.in_out", "In+Out") }
        static var cache: String { localized("menubar.status.cache", "Cache") }
        static var available: String { localized("menubar.status.available", "available") }
        static var notMounted: String { localized("menubar.status.not_mounted", "Not Mounted") }
        static var unavailable: String { localized("menubar.status.unavailable", "Unavailable") }
        static var refresh: String { localized("menubar.status.refresh", "Refresh Status") }
        static var emptyTitle: String { localized("menubar.status.empty_title", "No Telemetry Available") }
        static var errorTitle: String { localized("menubar.status.error_title", "Status Unavailable") }
        static var updating: String { localized("menubar.status.updating", "Updating status…") }

        static func pressureTitle(_ pressure: MemoryPressureLevel) -> String {
            switch pressure {
            case .normal: return localized("menubar.status.pressure_normal", "Normal")
            case .warning: return localized("menubar.status.pressure_warning", "Warning")
            case .critical: return localized("menubar.status.pressure_critical", "Critical")
            }
        }

        static func updated(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return String(format: localized("menubar.status.updated", "Updated %@"), formatter.string(from: date))
        }

        static func cores(_ count: Int) -> String { String(format: coresFormat, count) }
        static func cpuSummary(_ cpu: CPUStatusSnapshot) -> String {
            String(format: localized("menubar.status.cpu_summary", "CPU %@, %@ user, %@ system"), "\(Int(cpu.usage * 100))%", "\(Int(cpu.user * 100))%", "\(Int(cpu.system * 100))%")
        }
        static func memorySummary(_ memory: MemoryStatusSnapshot) -> String {
            String(format: localized("menubar.status.memory_summary", "Memory %@ used, %@"), "\(Int(memory.usageFraction * 100))%", pressureTitle(memory.pressure))
        }
        static func storageSummary(_ storage: StorageStatusSnapshot) -> String {
            let ssd = storage.ssdVolume.isMounted ? "\(Int(storage.ssdVolume.usageFraction * 100))%" : notMounted
            return String(format: localized("menubar.status.storage_summary", "Storage %@, SSD %@"), "\(Int(storage.systemVolume.usageFraction * 100))%", ssd)
        }
        static func total(_ value: String) -> String { String(format: totalFormat, value) }

        static func tokenSummary(_ usage: CLITokenUsageSnapshot) -> String {
            String(
                format: localized("menubar.status.token_summary", "Agent tokens %@ active"),
                usage.totalActiveTokens.formatted(.number)
            )
        }

        private static func localized(_ key: String, _ value: String) -> String {
            Bundle.main.localizedString(forKey: key, value: value, table: nil)
        }
    }
}
#endif
