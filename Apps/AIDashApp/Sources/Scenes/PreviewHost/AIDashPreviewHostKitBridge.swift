#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import AIDashCore
import AIDashUI
import DesignKit

public struct ClippedRevealLayout: Layout {
    public var progress: Double
    public init(progress: Double) { self.progress = min(max(progress, 0), 1) }
    public var animatableData: Double {
        get { progress }
        set { progress = min(max(newValue, 0), 1) }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let full = subview.sizeThatFits(proposal)
        return CGSize(width: full.width, height: full.height * progress)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let full = subview.sizeThatFits(.init(width: bounds.width, height: nil))
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: .init(width: bounds.width, height: full.height)
        )
    }
}

public enum PreviewSpeedMultiplier: Double, CaseIterable, Identifiable, Sendable {
    case normal = 1.0, half = 0.5, third = 0.35, quarter = 0.25
    public var id: Double { rawValue }
    public var label: String { "\(rawValue.formatted(.number.precision(.fractionLength(rawValue == 0.35 ? 2 : 1))))x" }
    public func spring(baseResponse: Double = 0.32, damping: Double = 0.84) -> Animation {
        .spring(response: baseResponse / rawValue, dampingFraction: damping)
    }
}

public struct PreviewVariantDescriptor: Identifiable, Equatable, Sendable {
    public let id, badgeCode, title, symbolName, topologySignature: String
    public let tab: DashboardWorkspaceSection
    public let metricTags: [String]

    public init(
        id: String, tab: DashboardWorkspaceSection, badgeCode: String,
        title: String, metricTags: [String], symbolName: String, topologySignature: String
    ) {
        self.id = id; self.tab = tab; self.badgeCode = badgeCode; self.title = title
        self.metricTags = metricTags; self.symbolName = symbolName; self.topologySignature = topologySignature
    }
}

public struct PreviewSelectionReceipt: Codable, Equatable, Sendable {
    public var schema: Int
    public var selectedVariantID: String
    public var starredVariantIDs: [String]
    public var notesByVariant: [String: String]
    public var updatedAt: String

    public init(
        schema: Int = 1, selectedVariantID: String = "", starredVariantIDs: [String] = [],
        notesByVariant: [String: String] = [:], updatedAt: String = PreviewSelectionReceipt.isoNow()
    ) {
        self.schema = schema; self.selectedVariantID = selectedVariantID
        self.starredVariantIDs = starredVariantIDs; self.notesByVariant = notesByVariant; self.updatedAt = updatedAt
    }

    public static func isoNow() -> String { ISO8601DateFormatter().string(from: Date()) }
    mutating func touch() { updatedAt = Self.isoNow() }
}

@MainActor
public final class PreviewSelectionReceiptWriter {
    public static var fallbackPath: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AIDash", isDirectory: true).appendingPathComponent("preview-selection.json")
    }

    private static var cachedReceiptsByPath: [String: PreviewSelectionReceipt] = [:]
    private static let ioQueue = DispatchQueue(label: "com.tianpli.aidash.preview-receipt-io", qos: .utility)

    public let path: URL
    public private(set) var receipt: PreviewSelectionReceipt
    private var selectionHandlers: [UUID: @MainActor (String) -> Void] = [:]
    private var summaryHandlers: [UUID: @MainActor (Int, Int) -> Void] = [:]

    public init(path: URL? = nil) {
        let envPath = ProcessInfo.processInfo.environment["AIDASH_PREVIEW_RECEIPT_PATH"].map { URL(fileURLWithPath: $0) }
        self.path = path ?? envPath ?? Self.fallbackPath
        self.receipt = Self.read(from: self.path)
    }

    public var summaryCounts: (selected: Int, starred: Int) {
        (receipt.selectedVariantID.isEmpty ? 0 : 1, receipt.starredVariantIDs.count)
    }

    @discardableResult
    public func observeSelection(_ handler: @escaping @MainActor (String) -> Void) -> UUID {
        let token = UUID(); selectionHandlers[token] = handler; return token
    }

    public func removeSelectionObserver(_ token: UUID) { selectionHandlers.removeValue(forKey: token) }

    @discardableResult
    public func observeSummary(_ handler: @escaping @MainActor (Int, Int) -> Void) -> UUID {
        let token = UUID(); summaryHandlers[token] = handler; return token
    }

    public func removeSummaryObserver(_ token: UUID) { summaryHandlers.removeValue(forKey: token) }

    @discardableResult
    public func select(_ id: String) -> String {
        receipt.selectedVariantID = receipt.selectedVariantID == id ? "" : id
        persist()
        let current = receipt.selectedVariantID
        for handler in selectionHandlers.values { handler(current) }
        return current
    }

    @discardableResult
    public func toggleStar(_ id: String) -> Bool {
        let nowStarred = !receipt.starredVariantIDs.contains(id)
        if nowStarred { receipt.starredVariantIDs.append(id) } else { receipt.starredVariantIDs.removeAll { $0 == id } }
        receipt.starredVariantIDs.sort()
        persist()
        return nowStarred
    }

    public func setNote(_ note: String, for id: String) {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            receipt.notesByVariant.removeValue(forKey: id)
        } else {
            receipt.notesByVariant[id] = note
        }
        persist(notifySummary: false)
    }

    public func persist(notifySummary: Bool = true) {
        receipt.touch()
        Self.write(receipt, to: path)
        guard notifySummary else { return }
        let counts = summaryCounts
        for handler in summaryHandlers.values { handler(counts.selected, counts.starred) }
    }

    public static func read(from path: URL = PreviewSelectionReceiptWriter.receiptPath()) -> PreviewSelectionReceipt {
        let key = path.standardizedFileURL.path
        if let cached = cachedReceiptsByPath[key] { return cached }
        guard !LiveDashboardTelemetryReader.isCloudDocsPath(path),
              let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode(PreviewSelectionReceipt.self, from: data) else {
            return PreviewSelectionReceipt()
        }
        cachedReceiptsByPath[key] = decoded
        return decoded
    }

    public static func write(_ receipt: PreviewSelectionReceipt, to path: URL = PreviewSelectionReceiptWriter.receiptPath()) {
        cachedReceiptsByPath[path.standardizedFileURL.path] = receipt
        let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        if isTest { writeAtomicallyToDisk(receipt, to: path) } else { ioQueue.async { writeAtomicallyToDisk(receipt, to: path) } }
    }

    private nonisolated static func writeAtomicallyToDisk(_ receipt: PreviewSelectionReceipt, to path: URL) {
        guard !path.path.contains("/Mobile Documents/com~apple~CloudDocs") else { return }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(receipt)
            let tmp = path.deletingLastPathComponent().appendingPathComponent(".preview-selection-\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: path.path) {
                _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: path)
            }
        } catch {}
    }

    public static func receiptPath() -> URL {
        ProcessInfo.processInfo.environment["AIDASH_PREVIEW_RECEIPT_PATH"].map { URL(fileURLWithPath: $0) } ?? fallbackPath
    }
}

private extension JSONEncoder {
    nonisolated static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public struct PreviewCLIQuota: Identifiable, Sendable, Equatable {
    public let id, name, reset, auth, deltaText: String
    public let usedFraction, burstUsedFraction, cacheHit: Double
    public let tokens: UInt64
    public let dailyUsageTrend: [Double]

    public init(
        id: String, name: String, usedFraction: Double, burstUsedFraction: Double,
        reset: String, tokens: UInt64, cacheHit: Double, auth: String,
        dailyUsageTrend: [Double] = [0.42, 0.39, 0.45, 0.36, 0.34, 0.31, 0.29], deltaText: String = "▼ -8%"
    ) {
        self.id = id; self.name = name; self.usedFraction = usedFraction
        self.burstUsedFraction = burstUsedFraction; self.reset = reset; self.tokens = tokens
        self.cacheHit = cacheHit; self.auth = auth; self.dailyUsageTrend = dailyUsageTrend; self.deltaText = deltaText
    }

    public var remaining: Double { max(0, 1 - usedFraction) }
}

public struct PreviewTokenPoint: Identifiable, Sendable, Equatable {
    public let id, label, cli: String
    public let activeTokens, cacheSaved: UInt64
    public let invocations, firstPassCount, reworkCount: Int

    public init(
        id: String, label: String, activeTokens: UInt64, cacheSaved: UInt64,
        invocations: Int, firstPassCount: Int? = nil, reworkCount: Int? = nil, cli: String
    ) {
        self.id = id; self.label = label; self.activeTokens = activeTokens
        self.cacheSaved = cacheSaved; self.invocations = invocations; self.cli = cli
        let resolvedFirstPass = firstPassCount ?? max(1, Int(Double(invocations) * 0.86))
        self.firstPassCount = resolvedFirstPass
        self.reworkCount = reworkCount ?? max(0, invocations - resolvedFirstPass)
    }
}

public struct PreviewRoleMetric: Identifiable, Sendable, Equatable {
    public let id, name, plainRoleTitle, durationDeltaText: String
    public let tokens: UInt64
    public let tokenShare, firstPassRate, avgMinutes: Double
    public let completedCount, reworkCount: Int
    public let durationTrend: [Double]

    public init(
        id: String, name: String, plainRoleTitle: String, tokens: UInt64, tokenShare: Double,
        firstPassRate: Double, completedCount: Int, reworkCount: Int,
        avgMinutes: Double, durationDeltaText: String, durationTrend: [Double]
    ) {
        self.id = id; self.name = name; self.plainRoleTitle = plainRoleTitle
        self.tokens = tokens; self.tokenShare = tokenShare; self.firstPassRate = firstPassRate
        self.completedCount = completedCount; self.reworkCount = reworkCount
        self.avgMinutes = avgMinutes; self.durationDeltaText = durationDeltaText; self.durationTrend = durationTrend
    }
}

public struct PreviewModelMetric: Identifiable, Sendable, Equatable {
    public let id, name, successDeltaText: String
    public let callCount, reworkCount: Int
    public let firstPassRate, speedTokensPerSec: Double
    public let tokensPerTask: UInt64
    public let trend14d: [Double]

    public init(
        id: String, name: String, callCount: Int, firstPassRate: Double, reworkCount: Int,
        tokensPerTask: UInt64, speedTokensPerSec: Double, successDeltaText: String, trend14d: [Double]
    ) {
        self.id = id; self.name = name; self.callCount = callCount; self.firstPassRate = firstPassRate
        self.reworkCount = reworkCount; self.tokensPerTask = tokensPerTask
        self.speedTokensPerSec = speedTokensPerSec; self.successDeltaText = successDeltaText; self.trend14d = trend14d
    }
}

public struct PreviewScheduledInspectionMetric: Identifiable, Sendable, Equatable {
    public let id, title, deltaText: String
    public let runs14d, issuesFound, autoFixed: Int
    public let trend14d: [Double]

    public init(id: String, title: String, runs14d: Int, issuesFound: Int, autoFixed: Int, deltaText: String, trend14d: [Double]) {
        self.id = id; self.title = title; self.runs14d = runs14d
        self.issuesFound = issuesFound; self.autoFixed = autoFixed; self.deltaText = deltaText; self.trend14d = trend14d
    }
}

public struct PreviewRepoTrendMetric: Identifiable, Sendable, Equatable {
    public let id, repoName, deltaText: String
    public let completedTasks30d, totalCalls30d: Int
    public let firstPassRate, avgTaskMinutes: Double
    public let activityTrend14d: [Double]

    public init(
        id: String, repoName: String, completedTasks30d: Int, totalCalls30d: Int,
        firstPassRate: Double, avgTaskMinutes: Double, deltaText: String, activityTrend14d: [Double]
    ) {
        self.id = id; self.repoName = repoName; self.completedTasks30d = completedTasks30d
        self.totalCalls30d = totalCalls30d; self.firstPassRate = firstPassRate
        self.avgTaskMinutes = avgTaskMinutes; self.deltaText = deltaText; self.activityTrend14d = activityTrend14d
    }
}

public struct PreviewSkillMetric: Identifiable, Sendable, Equatable {
    public let id, name, plainSummary, category, lastUsedText, deltaText: String
    public let calls30d, calls7d, reworkCount, scriptCalls30d: Int
    public let frequentDocsCount, rescueDocsCount, zeroReadDocsCount: Int
    public let firstPassRate, week1SuccessRate, scriptErrorRate, scriptAvgSeconds, weeklyDeltaPct: Double
    public let beforeOptSuccessRate, afterOptSuccessRate, beforeOptMinutes, afterOptMinutes: Double?
    public let optSummary: String?
    public let trend14d: [Double]
    public var isIdle: Bool { calls30d <= 2 }
}

@MainActor
public struct AIDashPreviewSampleData: Equatable {
    public let quotas: [PreviewCLIQuota]
    public let tokenPoints: [PreviewTokenPoint]
    public let roles: [PreviewRoleMetric]
    public let models: [PreviewModelMetric]
    public let inspections: [PreviewScheduledInspectionMetric]
    public let repos: [PreviewRepoTrendMetric]
    public let skills: [PreviewSkillMetric]

    public init(
        quotas: [PreviewCLIQuota], tokenPoints: [PreviewTokenPoint], roles: [PreviewRoleMetric],
        models: [PreviewModelMetric], inspections: [PreviewScheduledInspectionMetric],
        repos: [PreviewRepoTrendMetric], skills: [PreviewSkillMetric]
    ) {
        self.quotas = quotas; self.tokenPoints = tokenPoints; self.roles = roles
        self.models = models; self.inspections = inspections; self.repos = repos; self.skills = skills
    }

    public static func liveOrFallback() -> Self {
        let fallback = Self.fallback()
        let store = DashboardWorkspaceStore.shared
        let liveQuotas = store.cliEntries
            .filter { [.claude, .copilot, .codex, .kimi, .grok].contains($0.cliFilter) }
            .enumerated()
            .map { index, entry in
                let base = fallback.quotas[index % fallback.quotas.count]
                return PreviewCLIQuota(
                    id: entry.cliFilter.rawValue, name: entry.displayName,
                    usedFraction: entry.usedFraction, burstUsedFraction: entry.secondaryQuotaUsed ?? entry.usedFraction * 0.72,
                    reset: entry.quotaResetText ?? base.reset, tokens: entry.totalTokens > 0 ? entry.totalTokens : base.tokens,
                    cacheHit: entry.cacheHitFraction > 0 ? entry.cacheHitFraction : base.cacheHit,
                    auth: entry.authState.badgeTitle ?? "已登录正常",
                    dailyUsageTrend: base.dailyUsageTrend, deltaText: base.deltaText
                )
            }
        let livePoints = store.trendPoints.map { point in
            PreviewTokenPoint(
                id: point.id, label: point.bucketLabel,
                activeTokens: point.inputTokens + point.outputTokens,
                cacheSaved: point.cacheTokens, invocations: max(point.invocations, 8), cli: point.cliFilter.shortLabel
            )
        }
        return Self(
            quotas: liveQuotas.count >= 5 ? liveQuotas : fallback.quotas,
            tokenPoints: livePoints.count >= 14 ? livePoints : fallback.tokenPoints,
            roles: fallback.roles, models: fallback.models,
            inspections: fallback.inspections, repos: fallback.repos, skills: fallback.skills
        )
    }

    public static func fallback() -> Self {
        let quotas: [PreviewCLIQuota] = [
            PreviewCLIQuota(id: "claude", name: "Claude", usedFraction: 0.28, burstUsedFraction: 0.19, reset: "明天 08:00 重置", tokens: 245_000, cacheHit: 0.71, auth: "已登录正常", dailyUsageTrend: [0.46, 0.42, 0.39, 0.35, 0.33, 0.30, 0.28], deltaText: "▼ 今日省 14%"),
            PreviewCLIQuota(id: "copilot", name: "Copilot", usedFraction: 0.34, burstUsedFraction: 0.24, reset: "明天 09:00 重置", tokens: 318_000, cacheHit: 0.74, auth: "已登录正常", dailyUsageTrend: [0.51, 0.48, 0.44, 0.41, 0.38, 0.36, 0.34], deltaText: "▼ 今日省 11%"),
            PreviewCLIQuota(id: "codex", name: "Codex", usedFraction: 0.22, burstUsedFraction: 0.16, reset: "明天 10:00 重置", tokens: 186_000, cacheHit: 0.68, auth: "已登录正常", dailyUsageTrend: [0.38, 0.34, 0.31, 0.29, 0.27, 0.24, 0.22], deltaText: "▼ 今日省 16%"),
            PreviewCLIQuota(id: "kimi", name: "Kimi", usedFraction: 0.41, burstUsedFraction: 0.31, reset: "今晚 24:00 重置", tokens: 164_000, cacheHit: 0.64, auth: "建议刷新登录", dailyUsageTrend: [0.55, 0.52, 0.49, 0.47, 0.45, 0.43, 0.41], deltaText: "▼ 消耗趋稳"),
            PreviewCLIQuota(id: "grok", name: "Grok", usedFraction: 0.19, burstUsedFraction: 0.14, reset: "明天 12:00 重置", tokens: 142_000, cacheHit: 0.66, auth: "已登录正常", dailyUsageTrend: [0.33, 0.29, 0.28, 0.25, 0.23, 0.21, 0.19], deltaText: "▼ 额度充裕")
        ]
        let cliNames = ["Claude", "Copilot", "Codex", "Kimi", "Grok"]
        let points: [PreviewTokenPoint] = (0..<30).map { index in
            let day = index + 1
            let totalTasks = 10 + (index % 5) * 2 + index / 6
            let rework = max(1, 5 - index / 7 - (index % 2 == 0 ? 0 : 1))
            let active = UInt64(max(95_000, 215_000 - index * 3_100 + (index % 4) * 14_000))
            let saved = UInt64(90_000 + index * 5_400 + (index % 3) * 11_000)
            return PreviewTokenPoint(
                id: "day-\(day)", label: String(format: "11/%02d", max(1, day - 10)),
                activeTokens: active, cacheSaved: saved, invocations: totalTasks,
                firstPassCount: max(1, totalTasks - rework), reworkCount: rework, cli: cliNames[index % cliNames.count]
            )
        }
        let roles: [PreviewRoleMetric] = [
            PreviewRoleMetric(id: "steering", name: "Steering", plainRoleTitle: "总控调度", tokens: 1_180_000, tokenShare: 0.22, firstPassRate: 0.93, completedCount: 44, reworkCount: 3, avgMinutes: 2.1, durationDeltaText: "▼ -31%", durationTrend: [3.4, 3.1, 2.9, 2.6, 2.4, 2.2, 2.1]),
            PreviewRoleMetric(id: "designer", name: "Designer", plainRoleTitle: "界面设计", tokens: 960_000, tokenShare: 0.18, firstPassRate: 0.89, completedCount: 31, reworkCount: 4, avgMinutes: 4.3, durationDeltaText: "▼ -26%", durationTrend: [6.0, 5.6, 5.2, 4.9, 4.7, 4.5, 4.3]),
            PreviewRoleMetric(id: "writer", name: "Writer", plainRoleTitle: "代码编写", tokens: 2_310_000, tokenShare: 0.44, firstPassRate: 0.86, completedCount: 68, reworkCount: 9, avgMinutes: 6.4, durationDeltaText: "▼ -34%", durationTrend: [9.8, 9.1, 8.3, 7.6, 7.1, 6.7, 6.4]),
            PreviewRoleMetric(id: "reviewer", name: "Reviewer", plainRoleTitle: "质量审查", tokens: 840_000, tokenShare: 0.16, firstPassRate: 0.96, completedCount: 52, reworkCount: 2, avgMinutes: 1.8, durationDeltaText: "▼ -29%", durationTrend: [2.7, 2.5, 2.3, 2.1, 2.0, 1.9, 1.8])
        ]
        let models: [PreviewModelMetric] = [
            PreviewModelMetric(id: "argon", name: "Gemini 4 Argon", callCount: 412, firstPassRate: 0.93, reworkCount: 3, tokensPerTask: 62_000, speedTokensPerSec: 68, successDeltaText: "▲ +6.8%", trend14d: [0.84, 0.85, 0.87, 0.88, 0.90, 0.91, 0.93]),
            PreviewModelMetric(id: "claude", name: "Claude Opus", callCount: 356, firstPassRate: 0.90, reworkCount: 4, tokensPerTask: 76_000, speedTokensPerSec: 54, successDeltaText: "▲ +5.1%", trend14d: [0.83, 0.84, 0.85, 0.87, 0.88, 0.89, 0.90]),
            PreviewModelMetric(id: "gpt", name: "GPT-5.6", callCount: 289, firstPassRate: 0.87, reworkCount: 5, tokensPerTask: 71_000, speedTokensPerSec: 61, successDeltaText: "▲ +4.4%", trend14d: [0.81, 0.82, 0.83, 0.84, 0.85, 0.86, 0.87]),
            PreviewModelMetric(id: "grok", name: "Grok 4.7", callCount: 194, firstPassRate: 0.84, reworkCount: 6, tokensPerTask: 83_000, speedTokensPerSec: 74, successDeltaText: "▲ +3.9%", trend14d: [0.78, 0.79, 0.80, 0.81, 0.82, 0.83, 0.84])
        ]
        let inspections: [PreviewScheduledInspectionMetric] = [
            PreviewScheduledInspectionMetric(id: "aidata-digest", title: "数仓每日自愈与晨报生成", runs14d: 14, issuesFound: 6, autoFixed: 6, deltaText: "▲ 100% 自愈", trend14d: [0.85, 0.90, 0.92, 0.95, 0.98, 1.0, 1.0]),
            PreviewScheduledInspectionMetric(id: "daily-skill-retro", title: "Skill 每日自动复盘升级", runs14d: 14, issuesFound: 9, autoFixed: 8, deltaText: "▲ +19% 闭环", trend14d: [0.72, 0.76, 0.80, 0.84, 0.88, 0.91, 0.94]),
            PreviewScheduledInspectionMetric(id: "taste-evolution", title: "界面审美偏好自动沉淀", runs14d: 14, issuesFound: 4, autoFixed: 4, deltaText: "▲ 稳定运行", trend14d: [0.82, 0.86, 0.88, 0.91, 0.93, 0.95, 0.97]),
            PreviewScheduledInspectionMetric(id: "pr-supervisor", title: "PR 自动巡检与合并守护", runs14d: 28, issuesFound: 11, autoFixed: 10, deltaText: "▲ 91% 自动修复", trend14d: [0.75, 0.79, 0.83, 0.86, 0.88, 0.90, 0.91]),
            PreviewScheduledInspectionMetric(id: "crash-patrol", title: "卡死与异常日志自动排查", runs14d: 14, issuesFound: 3, autoFixed: 3, deltaText: "▼ 卡死归零", trend14d: [0.70, 0.78, 0.85, 0.90, 0.94, 0.98, 1.0]),
            PreviewScheduledInspectionMetric(id: "hygiene-gc", title: "临时分支与缓存自动清理", runs14d: 14, issuesFound: 7, autoFixed: 7, deltaText: "▲ 释放 18GB", trend14d: [0.88, 0.90, 0.92, 0.94, 0.96, 0.98, 1.0]),
            PreviewScheduledInspectionMetric(id: "linear-brief", title: "Linear 看板早间自动同步", runs14d: 14, issuesFound: 2, autoFixed: 2, deltaText: "▲ 零漏单", trend14d: [0.90, 0.92, 0.94, 0.95, 0.97, 0.99, 1.0])
        ]
        let repos: [PreviewRepoTrendMetric] = [
            PreviewRepoTrendMetric(id: "user-skills", repoName: "user-skills", completedTasks30d: 52, totalCalls30d: 1_120, firstPassRate: 0.91, avgTaskMinutes: 5.2, deltaText: "▲ +8.4%", activityTrend14d: [12, 14, 15, 17, 19, 21, 24]),
            PreviewRepoTrendMetric(id: "AIDash", repoName: "AIDash", completedTasks30d: 38, totalCalls30d: 860, firstPassRate: 0.89, avgTaskMinutes: 6.4, deltaText: "▲ +7.1%", activityTrend14d: [9, 11, 12, 14, 15, 18, 20]),
            PreviewRepoTrendMetric(id: "Financial", repoName: "Financial", completedTasks30d: 21, totalCalls30d: 490, firstPassRate: 0.87, avgTaskMinutes: 7.1, deltaText: "▲ +5.3%", activityTrend14d: [5, 6, 7, 8, 9, 11, 13]),
            PreviewRepoTrendMetric(id: "VitalStride", repoName: "VitalStride", completedTasks30d: 17, totalCalls30d: 370, firstPassRate: 0.85, avgTaskMinutes: 7.8, deltaText: "▲ +4.6%", activityTrend14d: [4, 5, 6, 6, 8, 9, 11])
        ]
        return Self(quotas: quotas, tokenPoints: points, roles: roles, models: models, inspections: inspections, repos: repos, skills: buildAll24Skills())
    }

    private struct SkillSeed {
        let name, summary, category, lastUsed, deltaText: String
        let calls30d: Int
        let rate, deltaPct: Double
        init(_ name: String, _ summary: String, _ category: String, _ calls30d: Int, _ lastUsed: String, _ rate: Double, _ deltaPct: Double, _ deltaText: String) {
            self.name = name; self.summary = summary; self.category = category; self.calls30d = calls30d
            self.lastUsed = lastUsed; self.rate = rate; self.deltaPct = deltaPct; self.deltaText = deltaText
        }
    }

    private static func buildAll24Skills() -> [PreviewSkillMetric] {
        let specs: [SkillSeed] = [
            SkillSeed("team-lead", "多任务总控调度与 PR 闭环交付", "总控与编排", 640, "10 分钟前", 0.94, 18.5, "▲ +18.5%"),
            SkillSeed("my-designer", "界面审美设计与双主题视觉验收", "界面与设计", 420, "18 分钟前", 0.92, 16.2, "▲ +16.2%"),
            SkillSeed("m2-dispatcher", "跨话题任务派发与进度巡检", "总控与编排", 355, "35 分钟前", 0.91, 14.0, "▲ +14.0%"),
            SkillSeed("code-review", "双轴代码质量审查与隐患拦截", "工程与构建", 310, "1 小时前", 0.95, 9.4, "▲ +9.4%"),
            SkillSeed("aidash-metrics", "数仓指标核验与看板口径对齐", "数据与复盘", 215, "2 小时前", 0.90, 12.8, "▲ +12.8%"),
            SkillSeed("xcode-cli", "Apple 编译构建与模拟器快速验证", "工程与构建", 180, "3 小时前", 0.88, 7.6, "▲ +7.6%"),
            SkillSeed("design-studio", "优秀设计灵感收集与配色沉淀", "界面与设计", 142, "今天 14:20", 0.91, 11.2, "▲ +11.2%"),
            SkillSeed("retro-loop", "每日异常复盘与自动改进回流", "数据与复盘", 118, "今天 09:10", 0.89, 8.9, "▲ +8.9%"),
            SkillSeed("skill-contract", "Skill 规范体检与门禁自动校验", "工程与构建", 96, "昨天", 0.93, 6.5, "▲ +6.5%"),
            SkillSeed("linear-board", "Linear 看板同步与每日晨报整理", "总控与编排", 82, "昨天", 0.92, 5.8, "▲ +5.8%"),
            SkillSeed("ios-concurrency-swiftui", "Swift 6 并发安全与丝滑交互打磨", "工程与构建", 68, "2 天前", 0.87, 9.1, "▲ +9.1%"),
            SkillSeed("ios-debugging-performance", "卡顿排查与独立应用签名打包", "工程与构建", 54, "2 天前", 0.86, -3.2, "▼ -3.2%"),
            SkillSeed("workflow-hub", "全链路研发流程串联与验收导航", "总控与编排", 44, "3 天前", 0.90, 4.2, "▲ +4.2%"),
            SkillSeed("layered-data-warehouse", "分层数仓建模与幂等增量校验", "数据与复盘", 36, "4 天前", 0.88, 5.0, "▲ +5.0%"),
            SkillSeed("ios-architecture-testing", "状态路由架构与无宿主快速单测", "工程与构建", 28, "5 天前", 0.87, -2.4, "▼ -2.4%"),
            SkillSeed("codebase-design", "模块边界梳理与架构决策记录", "工程与构建", 19, "6 天前", 0.89, 3.1, "▲ +3.1%"),
            SkillSeed("issue-brief", "清晰可读的任务单排版与摘要生成", "界面与设计", 14, "7 天前", 0.91, 2.5, "▲ +2.5%"),
            SkillSeed("deep-research", "多信源深度调研与交叉事实核验", "数据与复盘", 9, "9 天前", 0.86, -1.8, "▼ -1.8%"),
            SkillSeed("personal-m2-assistant", "个人自然语言意图拆解与批量派单", "总控与编排", 6, "11 天前", 0.88, 2.0, "▲ +2.0%"),
            SkillSeed("howto", "常用个人与工作流程速查指南", "总控与编排", 3, "14 天前", 0.85, 1.2, "▲ +1.2%"),
            SkillSeed("knowledge-digest", "科普文章与视频核心知识快速提炼", "数据与复盘", 3, "16 天前", 0.88, 0.8, "▲ +0.8%"),
            SkillSeed("story-craft", "项目成果提炼与技术博客生成", "数据与复盘", 0, "30 天未用", 0.84, 0.0, "▼ 闲置"),
            SkillSeed("asset-screener", "基金与宽基资产客观指标筛选", "数据与复盘", 0, "30 天未用", 0.85, 0.0, "▼ 闲置"),
            SkillSeed("nas-smart-home", "家庭 NAS 与米家智能家居运维", "工程与构建", 0, "30 天未用", 0.83, 0.0, "▼ 闲置")
        ]
        let optNotes = [
            "自动补齐了独立预览进程与防卡死检查规则", "自动收紧了大白话文案与时间趋势线默认模板",
            "自动缩短了后台巡检唤醒等待间隔", "自动合入高频问题防漏检清单", "自动精简了冗余说明段落，加载更快"
        ]
        return specs.enumerated().map { idx, item in
            let calls30d = item.calls30d
            let calls7d = calls30d == 0 ? 0 : max(1, Int(Double(calls30d) * 0.28))
            let trend: [Double] = (0..<14).map { step in
                guard calls30d > 0 else { return 0 }
                let base = Double(max(1, calls30d / 20))
                let slope = item.deltaPct >= 0 ? Double(step) * 0.45 : Double(14 - step) * 0.25
                return base + slope + Double((idx + step) % 3)
            }
            return PreviewSkillMetric(
                id: item.name, name: item.name, plainSummary: item.summary, category: item.category,
                lastUsedText: item.lastUsed, deltaText: item.deltaText, calls30d: calls30d, calls7d: calls7d,
                reworkCount: calls30d == 0 ? 0 : max(1, (24 - idx) / 5),
                scriptCalls30d: calls30d == 0 ? 0 : calls30d * 2 - idx * 3,
                frequentDocsCount: calls30d > 50 ? 4 : (calls30d > 0 ? 2 : 0),
                rescueDocsCount: calls30d > 0 ? 2 : 1, zeroReadDocsCount: idx % 4 == 0 ? 1 : 0,
                firstPassRate: item.rate, week1SuccessRate: max(0.68, item.rate - 0.14),
                scriptErrorRate: max(0.004, 0.026 - Double(idx % 5) * 0.004),
                scriptAvgSeconds: 0.6 + Double(idx % 6) * 0.45, weeklyDeltaPct: item.deltaPct,
                beforeOptSuccessRate: idx < 5 ? max(0.69, item.rate - 0.19) : nil,
                afterOptSuccessRate: idx < 5 ? item.rate : nil,
                beforeOptMinutes: idx < 5 ? 9.6 - Double(idx) * 0.7 : nil,
                afterOptMinutes: idx < 5 ? 5.4 - Double(idx) * 0.4 : nil,
                optSummary: idx < 5 ? optNotes[idx] : nil, trend14d: trend
            )
        }
    }
}

public extension SkillInspectorDetail {
    var l0TokensEst: Int { max(frontmatterTokensEst + bodyTokensEst, max(skillMdLines * 14, 420)) }
    var computedRefsTokensEst: Int { references.reduce(0) { $0 + max($1.tokensEst, $1.lineCount * 12) } }
    var totalBundleTokensEst: Int { l0TokensEst + computedRefsTokensEst }
    var bundleKB: Double { Double(totalBundleTokensEst) * 4 / 1024 }
    var refsKB: Double { Double(computedRefsTokensEst) * 4 / 1024 }
    var totalScriptCalls30d: Int { scripts.compactMap(\.calls30d).reduce(0, +) }
    var previewCategoryName: String {
        switch skill {
        case "team-lead", "m2-dispatcher", "workflow-hub", "linear-board", "personal-m2-assistant", "howto": return "总控与编排"
        case "my-designer", "design-studio", "issue-brief": return "界面与设计"
        case "aidash-metrics", "layered-data-warehouse", "retro-loop", "deep-research", "knowledge-digest", "story-craft", "asset-screener", "portfolio-advisor": return "数据与复盘"
        default: return "工程与构建"
        }
    }
}

public struct PreviewSparkline: View {
    public let values: [Double], tint: Color, height: CGFloat
    public init(values: [Double], tint: Color = .green, height: CGFloat = 24) {
        self.values = values; self.tint = tint; self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let safe = values.isEmpty ? [0, 1] : values
            let minVal = safe.min() ?? 0
            let span = max((safe.max() ?? 1) - minVal, 0.0001)
            Path { path in
                for (index, val) in safe.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(safe.count - 1, 1))
                    let y = proxy.size.height * (1 - CGFloat((val - minVal) / span) * 0.82 - 0.09)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
    }
}

public struct PreviewPill: View {
    public let title: String, tint: Color
    public init(_ title: String, tint: Color = .secondary) { self.title = title; self.tint = tint }
    public var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.13), in: Capsule())
    }
}

public struct PreviewMetricBar: View {
    public let label, valueText: String
    public let value: Double
    public let tint: Color
    public init(label: String, value: Double, valueText: String, tint: Color = .accentColor) {
        self.label = label; self.value = value; self.valueText = valueText; self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 6)
                Text(valueText).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            GeometryReader { proxy in
                Capsule().fill(Color.secondary.opacity(0.12)).overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 7)
        }
    }
}

public struct PreviewRing: View {
    public let value: Double, tint: Color, label: String, size: CGFloat
    public init(value: Double, tint: Color, label: String, size: CGFloat = 74) {
        self.value = value; self.tint = tint; self.label = label; self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 7)
            Circle().trim(from: 0, to: min(max(value, 0.02), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.caption.weight(.bold).monospacedDigit())
        }
        .frame(width: size, height: size)
    }
}

public struct PreviewSurface<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.18)))
    }
}
#endif
