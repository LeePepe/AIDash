#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import AIDashCore
import AIDashUI
import DesignKit

public struct ClippedRevealLayout: Layout {
    public var progress: Double

    public init(progress: Double) {
        self.progress = min(max(progress, 0), 1)
    }

    public var animatableData: Double {
        get { progress }
        set { progress = min(max(newValue, 0), 1) }
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let full = subview.sizeThatFits(proposal)
        return CGSize(width: full.width, height: full.height * progress)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
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
    case normal = 1.0
    case half = 0.5
    case third = 0.35
    case quarter = 0.25

    public var id: Double { rawValue }
    public var label: String { "\(rawValue.formatted(.number.precision(.fractionLength(rawValue == 0.35 ? 2 : 1))))x" }

    public func spring(baseResponse: Double = 0.32, damping: Double = 0.84) -> Animation {
        .spring(response: baseResponse / rawValue, dampingFraction: damping)
    }
}

public struct PreviewVariantDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let tab: DashboardWorkspaceSection
    public let badgeCode: String
    public let title: String
    public let metricTags: [String]
    public let symbolName: String
    public let topologySignature: String

    public init(
        id: String,
        tab: DashboardWorkspaceSection,
        badgeCode: String,
        title: String,
        metricTags: [String],
        symbolName: String,
        topologySignature: String
    ) {
        self.id = id
        self.tab = tab
        self.badgeCode = badgeCode
        self.title = title
        self.metricTags = metricTags
        self.symbolName = symbolName
        self.topologySignature = topologySignature
    }
}

public struct PreviewSelectionReceipt: Codable, Equatable, Sendable {
    public var schema: Int
    public var selectedVariantID: String
    public var starredVariantIDs: [String]
    public var notesByVariant: [String: String]
    public var updatedAt: String

    public init(
        schema: Int = 1,
        selectedVariantID: String = "",
        starredVariantIDs: [String] = [],
        notesByVariant: [String: String] = [:],
        updatedAt: String = PreviewSelectionReceipt.isoNow()
    ) {
        self.schema = schema
        self.selectedVariantID = selectedVariantID
        self.starredVariantIDs = starredVariantIDs
        self.notesByVariant = notesByVariant
        self.updatedAt = updatedAt
    }

    public static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    mutating func touch() {
        updatedAt = Self.isoNow()
    }
}

@MainActor
public final class PreviewSelectionReceiptWriter: ObservableObject {
    public static var fallbackPath: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AIDash", isDirectory: true)
            .appendingPathComponent("preview-selection.json")
    }

    public let path: URL
    @Published public private(set) var receipt: PreviewSelectionReceipt

    public init(path: URL? = nil) {
        let environmentPath = ProcessInfo.processInfo.environment["AIDASH_PREVIEW_RECEIPT_PATH"]
        self.path = path
            ?? environmentPath.map { URL(fileURLWithPath: $0) }
            ?? Self.fallbackPath
        self.receipt = Self.read(from: self.path)
    }

    public func select(_ id: String) {
        receipt.selectedVariantID = receipt.selectedVariantID == id ? "" : id
        persist()
    }

    public func toggleStar(_ id: String) {
        if receipt.starredVariantIDs.contains(id) {
            receipt.starredVariantIDs.removeAll { $0 == id }
        } else {
            receipt.starredVariantIDs.append(id)
        }
        receipt.starredVariantIDs.sort()
        persist()
    }

    public func setNote(_ note: String, for id: String) {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            receipt.notesByVariant.removeValue(forKey: id)
        } else {
            receipt.notesByVariant[id] = note
        }
        persist()
    }

    public func persist() {
        receipt.touch()
        Self.write(receipt, to: path)
        objectWillChange.send()
    }

    public static func read(from path: URL = PreviewSelectionReceiptWriter.receiptPath()) -> PreviewSelectionReceipt {
        guard let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode(PreviewSelectionReceipt.self, from: data) else {
            return PreviewSelectionReceipt()
        }
        return decoded
    }

    public static func write(_ receipt: PreviewSelectionReceipt, to path: URL = PreviewSelectionReceiptWriter.receiptPath()) {
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(receipt)
            let temporaryURL = path.deletingLastPathComponent()
                .appendingPathComponent(".preview-selection-\(UUID().uuidString).tmp")
            try data.write(to: temporaryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: path.path) {
                _ = try FileManager.default.replaceItemAt(path, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: path)
            }
        } catch {
            // Receipt persistence is best effort; the gallery remains usable when
            // the handoff volume is unavailable in a hermetic test process.
        }
    }

    public static func receiptPath() -> URL {
        ProcessInfo.processInfo.environment["AIDASH_PREVIEW_RECEIPT_PATH"]
            .map { URL(fileURLWithPath: $0) }
            ?? fallbackPath
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public struct PreviewCLIQuota: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let usedFraction: Double
    public let burstUsedFraction: Double
    public let reset: String
    public let tokens: UInt64
    public let cacheHit: Double
    public let auth: String

    public init(
        id: String,
        name: String,
        usedFraction: Double,
        burstUsedFraction: Double,
        reset: String,
        tokens: UInt64,
        cacheHit: Double,
        auth: String
    ) {
        self.id = id
        self.name = name
        self.usedFraction = usedFraction
        self.burstUsedFraction = burstUsedFraction
        self.reset = reset
        self.tokens = tokens
        self.cacheHit = cacheHit
        self.auth = auth
    }

    public var remaining: Double { max(0, 1 - usedFraction) }
}

public struct PreviewTokenPoint: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let activeTokens: UInt64
    public let cacheSaved: UInt64
    public let invocations: Int
    public let cli: String

    public init(id: String, label: String, activeTokens: UInt64, cacheSaved: UInt64, invocations: Int, cli: String) {
        self.id = id
        self.label = label
        self.activeTokens = activeTokens
        self.cacheSaved = cacheSaved
        self.invocations = invocations
        self.cli = cli
    }
}

public struct PreviewRoleMetric: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let tokens: UInt64
    public let tokenShare: Double
    public let r1Rate: Double
    public let r1: Int
    public let r2: Int
    public let r3: Int
    public let p50: Double
    public let p90: Double

    public init(id: String, name: String, tokens: UInt64, tokenShare: Double, r1Rate: Double, r1: Int, r2: Int, r3: Int, p50: Double, p90: Double) {
        self.id = id; self.name = name; self.tokens = tokens; self.tokenShare = tokenShare
        self.r1Rate = r1Rate; self.r1 = r1; self.r2 = r2; self.r3 = r3; self.p50 = p50; self.p90 = p90
    }
}

public struct PreviewModelMetric: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let r1Rate: Double
    public let churn: Int
    public let tokensPerTask: UInt64
    public let speed: Double

    public init(id: String, name: String, r1Rate: Double, churn: Int, tokensPerTask: UInt64, speed: Double) {
        self.id = id; self.name = name; self.r1Rate = r1Rate; self.churn = churn; self.tokensPerTask = tokensPerTask; self.speed = speed
    }
}

public struct PreviewSkillMetric: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let category: String
    public let bundleKB: Double
    public let refsKB: Double
    public let unpracticedRate: Double
    public let unhitRefsCount: Int
    public let r1Rate: Double
    public let roiScore: Double
    public let scripts: Int
    public let scriptCalls: Int
    public let docPreview: String
    public let editChurn: Int
    public let implBugEscapes: Int
    public let specGapEscapes: Int
    public let evalCases: Int

    public init(id: String, name: String, category: String, bundleKB: Double, refsKB: Double, unpracticedRate: Double, unhitRefsCount: Int, r1Rate: Double, roiScore: Double, scripts: Int, scriptCalls: Int, docPreview: String, editChurn: Int, implBugEscapes: Int, specGapEscapes: Int, evalCases: Int) {
        self.id = id; self.name = name; self.category = category; self.bundleKB = bundleKB; self.refsKB = refsKB
        self.unpracticedRate = unpracticedRate; self.unhitRefsCount = unhitRefsCount; self.r1Rate = r1Rate; self.roiScore = roiScore
        self.scripts = scripts; self.scriptCalls = scriptCalls; self.docPreview = docPreview; self.editChurn = editChurn
        self.implBugEscapes = implBugEscapes; self.specGapEscapes = specGapEscapes; self.evalCases = evalCases
    }
}

@MainActor
public struct AIDashPreviewSampleData: Equatable {
    public let quotas: [PreviewCLIQuota]
    public let tokenPoints: [PreviewTokenPoint]
    public let roles: [PreviewRoleMetric]
    public let models: [PreviewModelMetric]
    public let skills: [PreviewSkillMetric]

    public init(
        quotas: [PreviewCLIQuota],
        tokenPoints: [PreviewTokenPoint],
        roles: [PreviewRoleMetric],
        models: [PreviewModelMetric],
        skills: [PreviewSkillMetric]
    ) {
        self.quotas = quotas; self.tokenPoints = tokenPoints; self.roles = roles; self.models = models; self.skills = skills
    }

    public static func liveOrFallback() -> Self {
        let store = DashboardWorkspaceStore.shared
        let summary = store.liveEfficiencySummary ?? LiveDashboardTelemetryReader.loadLiveEfficiencySummary()
        let liveQuotas = store.cliEntries
            .filter { [.claude, .copilot, .codex, .kimi, .grok].contains($0.cliFilter) }
            .map { entry in
                PreviewCLIQuota(
                    id: entry.cliFilter.rawValue,
                    name: entry.displayName,
                    usedFraction: entry.usedFraction,
                    burstUsedFraction: entry.secondaryQuotaUsed ?? entry.usedFraction * 0.72,
                    reset: entry.quotaResetText ?? "Reset window ready",
                    tokens: entry.totalTokens,
                    cacheHit: entry.cacheHitFraction,
                    auth: entry.authState.badgeTitle ?? "Authenticated"
                )
            }
        let livePoints = store.trendPoints.map {
            PreviewTokenPoint(id: $0.id, label: $0.bucketLabel, activeTokens: $0.inputTokens + $0.outputTokens, cacheSaved: $0.cacheTokens, invocations: $0.invocations, cli: $0.cliFilter.shortLabel)
        }
        let liveRoles = summary?.agentEfficiency?.roles.compactMap { row -> PreviewRoleMetric? in
            guard ["steering", "designer", "writer", "reviewer", "m1", "m2"].contains(row.roleKey.lowercased()) else { return nil }
            return PreviewRoleMetric(id: row.roleKey, name: row.roleLabelEn ?? row.roleLabel, tokens: row.estimatedTokens, tokenShare: row.tokenSharePct / 100, r1Rate: row.r1PassRate ?? 0.84, r1: row.r1Count, r2: row.r2Count, r3: row.r3PlusCount, p50: row.medianDurationSec ?? 90, p90: row.p90DurationSec ?? 180)
        } ?? []
        let liveSkills = summary?.skillsROI.map { report in
            report.skillDetails.filter { !$0.isGhost }.map { detail in
                PreviewSkillMetric(
                    id: detail.skill,
                    name: detail.skill,
                    category: detail.previewCategoryName,
                    bundleKB: detail.bundleKB,
                    refsKB: detail.refsKB,
                    unpracticedRate: detail.unpracticedRate ?? 0,
                    unhitRefsCount: detail.unhitRefsCount,
                    r1Rate: detail.r1PassRate ?? 0.82,
                    roiScore: detail.roiScore ?? 1.0,
                    scripts: detail.scripts.count,
                    scriptCalls: detail.totalScriptCalls30d,
                    docPreview: detail.docPreview ?? "SKILL.md preview available",
                    editChurn: detail.editChurn,
                    implBugEscapes: detail.implBugEscapes,
                    specGapEscapes: detail.specGapEscapes,
                    evalCases: detail.evalCases.count
                )
            }
        } ?? []
        let fallback = Self.fallback()
        return Self(
            quotas: liveQuotas.count >= 5 ? liveQuotas : fallback.quotas,
            tokenPoints: livePoints.count >= 7 ? livePoints : fallback.tokenPoints,
            roles: liveRoles.count >= 4 ? liveRoles : fallback.roles,
            models: fallback.models,
            skills: liveSkills.count >= 4 ? liveSkills : fallback.skills
        )
    }

    public static func fallback() -> Self {
        let quotaNames = [("claude", "Claude"), ("copilot", "Copilot"), ("codex", "Codex"), ("kimi", "Kimi"), ("grok", "Grok")]
        let quotas = quotaNames.enumerated().map { index, item in
            PreviewCLIQuota(id: item.0, name: item.1, usedFraction: 0.28 + Double(index) * 0.095, burstUsedFraction: 0.18 + Double(index) * 0.08, reset: "Reset 11-21 \(String(format: "%02d:00", 8 + index))", tokens: UInt64(210_000 + index * 73_000), cacheHit: 0.62 + Double(index) * 0.045, auth: index == 3 ? "OAuth refresh due" : "Authenticated")
        }
        let points = (0..<14).map { index in
            PreviewTokenPoint(id: "day-\(index)", label: "11/\(String(format: "%02d", 7 + index))", activeTokens: UInt64(92_000 + index * 17_000 + (index % 3) * 31_000), cacheSaved: UInt64(45_000 + index * 8_000), invocations: 18 + index * 3, cli: quotaNames[index % quotaNames.count].1)
        }
        let roles = [
            PreviewRoleMetric(id: "steering", name: "Steering", tokens: 1_240_000, tokenShare: 0.23, r1Rate: 0.91, r1: 41, r2: 3, r3: 1, p50: 74, p90: 188),
            PreviewRoleMetric(id: "designer", name: "Designer", tokens: 1_010_000, tokenShare: 0.19, r1Rate: 0.87, r1: 34, r2: 5, r3: 2, p50: 112, p90: 264),
            PreviewRoleMetric(id: "writer", name: "Writer", tokens: 2_280_000, tokenShare: 0.42, r1Rate: 0.83, r1: 52, r2: 8, r3: 3, p50: 196, p90: 522),
            PreviewRoleMetric(id: "reviewer", name: "Reviewer", tokens: 870_000, tokenShare: 0.16, r1Rate: 0.95, r1: 47, r2: 2, r3: 0, p50: 64, p90: 146)
        ]
        let models = [
            PreviewModelMetric(id: "argon", name: "Gemini 4 Argon", r1Rate: 0.94, churn: 2, tokensPerTask: 64_000, speed: 41),
            PreviewModelMetric(id: "claude", name: "Claude", r1Rate: 0.89, churn: 4, tokensPerTask: 78_000, speed: 52),
            PreviewModelMetric(id: "gpt", name: "GPT", r1Rate: 0.86, churn: 5, tokensPerTask: 72_000, speed: 47),
            PreviewModelMetric(id: "grok", name: "Grok", r1Rate: 0.81, churn: 7, tokensPerTask: 91_000, speed: 63)
        ]
        let names = ["team-lead", "my-designer", "retro-loop", "repo-kit", "skill-contract", "xcode-cli"]
        let skills = names.enumerated().map { index, name in
            let category = index < 2 ? "Orchestration" : (index < 4 ? "Data & Retro" : "Engineering Delivery")
            return PreviewSkillMetric(
                id: name,
                name: name,
                category: category,
                bundleKB: 34 + Double(index * 9),
                refsKB: 18 + Double(index * 4),
                unpracticedRate: 0.16 + Double(index) * 0.095,
                unhitRefsCount: index % 3,
                r1Rate: 0.76 + Double(index % 4) * 0.055,
                roiScore: 1.1 + Double(index) * 0.18,
                scripts: 2 + index % 3,
                scriptCalls: 9 + index * 4,
                docPreview: "Progressive contract for \(name)\n\nL0 entry with references and deterministic gates.",
                editChurn: 2 + index,
                implBugEscapes: index % 3,
                specGapEscapes: (index + 1) % 3,
                evalCases: 4 + index
            )
        }
        return Self(quotas: quotas, tokenPoints: points, roles: roles, models: models, skills: skills)
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
        case "team-lead", "m2-dispatcher", "workflow-hub", "linear-board", "personal-m2-assistant", "howto": return "Orchestration"
        case "my-designer", "design-studio", "issue-brief": return "Product Design"
        case "aidash-metrics", "layered-data-warehouse", "retro-loop", "deep-research", "knowledge-digest", "story-craft", "asset-screener", "portfolio-advisor": return "Data & Retro"
        default: return "Engineering Delivery"
        }
    }
}

public struct PreviewPill: View {
    public let title: String
    public let tint: Color

    public init(_ title: String, tint: Color = .secondary) {
        self.title = title; self.tint = tint
    }

    public var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.13), in: Capsule())
    }
}

public struct PreviewMetricBar: View {
    public let label: String
    public let value: Double
    public let valueText: String
    public let tint: Color

    public init(label: String, value: Double, valueText: String, tint: Color = .accentColor) {
        self.label = label; self.value = value; self.valueText = valueText; self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text(valueText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
    public let value: Double
    public let tint: Color
    public let label: String
    public let size: CGFloat

    public init(value: Double, tint: Color, label: String, size: CGFloat = 78) {
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
