#if os(macOS)
import Foundation

/// Observations are never inferred from render time, file mtime, or a missing numeric value.
public struct SkillsObservationMetadata: Decodable, Sendable, Equatable {
    public let window: String?
    public let start: String?
    public let end: String?
    public let asOf: String?
    public let sample: Int?
    public let coverage: String?
    public let estimated: Bool?
    public let method: String?
    private let present: Set<String>

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SkillsKey.self)
        present = Set(c.allKeys.map(\.stringValue))
        window = try c.decodeIfPresent(String.self, forKey: .init("window_cst"))
        start = try c.decodeIfPresent(String.self, forKey: .init("window_start"))
        end = try c.decodeIfPresent(String.self, forKey: .init("window_end"))
        asOf = try c.decodeIfPresent(String.self, forKey: .init("source_as_of"))
        sample = try c.decodeIfPresent(Int.self, forKey: .init("sample_size"))
        coverage = try c.decodeIfPresent(String.self, forKey: .init("coverage_status"))
        estimated = try c.decodeIfPresent(Bool.self, forKey: .init("estimated"))
        method = try c.decodeIfPresent(String.self, forKey: .init("estimation_method"))
    }

    private init(window: String?, start: String?, end: String?, asOf: String?, sample: Int?, coverage: String?, estimated: Bool?, method: String?, present: Set<String>) {
        self.window = window; self.start = start; self.end = end; self.asOf = asOf
        self.sample = sample; self.coverage = coverage; self.estimated = estimated; self.method = method
        self.present = present
    }

    func inheriting(_ parent: Self) -> Self {
        .init(window: present.contains("window_cst") ? window : parent.window,
              start: present.contains("window_start") ? start : parent.start,
              end: present.contains("window_end") ? end : parent.end,
              asOf: present.contains("source_as_of") ? asOf : parent.asOf,
              sample: present.contains("sample_size") ? sample : parent.sample,
              coverage: present.contains("coverage_status") ? coverage : parent.coverage,
              estimated: present.contains("estimated") ? estimated : parent.estimated,
              method: present.contains("estimation_method") ? method : parent.method,
              present: present.union(parent.present))
    }

    var hasSamples: Bool { (sample ?? 0) > 0 && !["missing", "unknown", "error"].contains(coverage ?? "unknown") }
}

public struct SkillsMetric<Value: Decodable & Sendable & Equatable>: Sendable, Equatable {
    public let value: Value?
    public let metadata: SkillsObservationMetadata
}

private struct SkillsKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

/// The producer has scalar fields and some population/metric envelopes. Only `.value`
/// is unwrapped; arbitrary dictionaries and arrays never become display strings.
private protocol SkillsObjectPopulation: Decodable {}

private struct SkillsObserved<Value: Decodable>: Decodable {
    let value: Value?
    let metadata: SkillsObservationMetadata?
    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: SkillsKey.self), c.contains(.init("value")) {
            value = Value.self is any SkillsObjectPopulation.Type
                ? try Value(from: decoder) : try c.decodeIfPresent(Value.self, forKey: .init("value"))
            metadata = try SkillsObservationMetadata(from: decoder)
        } else {
            value = try decoder.singleValueContainer().decode(Value?.self)
            metadata = nil
        }
    }
}

private struct SkillsFields {
    let container: KeyedDecodingContainer<SkillsKey>
    let metadata: SkillsObservationMetadata
    init(_ decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: SkillsKey.self)
        let parent = try SkillsObservationMetadata(from: decoder)
        if outer.contains(.init("value")), let nested = try? outer.superDecoder(forKey: .init("value")),
           let inner = try? nested.container(keyedBy: SkillsKey.self) {
            container = inner
            metadata = try SkillsObservationMetadata(from: nested).inheriting(parent)
        } else {
            container = outer
            metadata = parent
        }
    }
    func metric<T: Decodable & Sendable & Equatable>(_ key: String) throws -> SkillsMetric<T> {
        let observed = try container.decodeIfPresent(SkillsObserved<T>.self, forKey: .init(key))
        return SkillsMetric(value: observed?.value, metadata: observed?.metadata?.inheriting(metadata) ?? metadata)
    }
    func value<T: Decodable>(_ key: String, as type: T.Type = T.self) throws -> T? {
        try container.decodeIfPresent(SkillsObserved<T>.self, forKey: .init(key))?.value
    }
}

public struct SkillsPinHealth: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata
    public let behind: SkillsMetric<Int>
    public let synchronized: SkillsMetric<Bool>
    public let consumers: [SkillsPinConsumer]
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        behind = try f.metric("outdated_pin_count"); synchronized = try f.metric("all_up_to_date")
        consumers = try f.value("consumers") ?? []
    }
}

public struct SkillsPinConsumer: Decodable, Sendable, Equatable {
    public let repo: String?
    public let outdated: Bool?
}

public struct SkillsGateHealth: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata
    public let runs: SkillsMetric<Int>
    public let catches: SkillsMetric<Int>
    public let noise: SkillsMetric<Int>
    public let catchRate: SkillsMetric<Double>
    public let noiseRate: SkillsMetric<Double>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        runs = try f.metric("total_runs_7d"); catches = try f.metric("true_positive_catches_7d")
        noise = try f.metric("config_or_rerun_noise_7d")
        catchRate = try f.metric("gate_catch_rate"); noiseRate = try f.metric("noise_rate")
    }
}

public struct SkillsAuditHealth: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata
    public let total: SkillsMetric<Int>
    public let passed: SkillsMetric<Int>
    public let evals: SkillsMetric<Int>
    public let evalDelta: SkillsMetric<Int>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        total = try f.metric("total_skills"); passed = try f.metric("audit_pass_count")
        evals = try f.metric("eval_case_total"); evalDelta = try f.metric("eval_case_weekly_delta")
    }
}

public struct SkillsUsageRow: Decodable, Sendable, Equatable {
    public let skill: String
    public let metadata: SkillsObservationMetadata
    public let loads7d: SkillsMetric<Int>
    public let loads30d: SkillsMetric<Int>
    public let roi: SkillsMetric<Double>
    public let r1Total: SkillsMetric<Int>
    public let r1Pass: SkillsMetric<Double>
    public let touch: SkillsMetric<Double>
    public let unpracticed: SkillsMetric<Double>
    public let scriptExecs: SkillsMetric<Int>
    public let diagnosis: String?
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        skill = try f.container.decode(String.self, forKey: .init("skill"))
        loads7d = try f.metric("loads_7d"); loads30d = try f.metric("loads_30d")
        roi = try f.metric("roi_score")
        let reviews = try f.value("r1_freshness", as: SkillsObservationMetadata.self)
        let total: SkillsMetric<Int> = try f.metric("r1_total")
        let pass: SkillsMetric<Double> = try f.metric("r1_pass_rate")
        r1Total = SkillsMetric(value: total.value, metadata: reviews ?? total.metadata)
        r1Pass = SkillsMetric(value: pass.value, metadata: reviews ?? pass.metadata)
        touch = try f.metric("script_touch_rate"); unpracticed = try f.metric("unpracticed_rate")
        scriptExecs = try f.metric("script_execs"); diagnosis = try f.value("diagnosis")
    }
}

public struct SkillsUsagePopulation: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata
    public let active: SkillsMetric<Int>
    public let idle: [String]
    public let top: [SkillsUsageRow]
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        active = try f.metric("active_skills_count"); idle = try f.value("idle_skills_30d") ?? []
        top = try f.value("top_used_skills") ?? []
    }
}

public struct SkillsDisclosureRow: Decodable, Sendable, Equatable {
    public let skill: String
    public let metadata: SkillsObservationMetadata
    public let l0: SkillsMetric<Double>
    public let l1: SkillsMetric<Double>
    public let greedy: SkillsMetric<Double>
    public let contextTokens: SkillsMetric<Double>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        skill = try f.container.decode(String.self, forKey: .init("skill"))
        l0 = try f.metric("l0_only_rate"); l1 = try f.metric("l1_selective_rate")
        greedy = try f.metric("l1_greedy_violation_rate"); contextTokens = try f.metric("avg_context_tokens")
    }
}

public struct SkillsChurnRow: Decodable, Sendable, Equatable {
    public let skill: String
    public let metadata: SkillsObservationMetadata
    public let edits: SkillsMetric<Int>
    public let retries: SkillsMetric<Int>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        skill = try f.container.decode(String.self, forKey: .init("skill"))
        edits = try f.metric("edit_churn_count"); retries = try f.metric("retry_commands")
    }
}

public struct SkillsEscapeRow: Decodable, Sendable, Equatable {
    public let skill: String
    public let metadata: SkillsObservationMetadata
    public let implementation: SkillsMetric<Int>
    public let specification: SkillsMetric<Int>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        skill = try f.container.decode(String.self, forKey: .init("skill"))
        implementation = try f.metric("impl_bug_escapes"); specification = try f.metric("spec_gap_escapes")
    }
}

public struct SkillsContextSlice: Decodable, Sendable, Equatable {
    public let key: String
    public let metadata: SkillsObservationMetadata
    public let tokens: SkillsMetric<Double>
    public let share: SkillsMetric<Double>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        key = try f.container.decode(String.self, forKey: .init("slice_key"))
        tokens = try f.metric("tokens"); share = try f.metric("share_pct")
    }
}

public struct SkillsContextHealth: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata
    public let slices: [SkillsContextSlice]
    public let total: SkillsMetric<Double>
    public let cacheHitPercent: SkillsMetric<Double>
    public let savedTokens: SkillsMetric<Double>
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        slices = try f.value("slices") ?? []; total = try f.metric("total_context_tokens")
        let hit: SkillsMetric<Double> = try f.metric("kv_cache_hit_pct")
        let cacheMetadata = try f.value("kv_cache_freshness", as: SkillsObservationMetadata.self)
        cacheHitPercent = SkillsMetric(value: hit.value, metadata: cacheMetadata ?? hit.metadata)
        savedTokens = try f.metric("compressed_saved_tokens")
    }
}

public struct SkillsToolBurnRow: Decodable, Sendable, Equatable {
    public let tool: String
    public let metadata: SkillsObservationMetadata
    public let calls: SkillsMetric<Int>
    public let total: SkillsMetric<Double>
    public let p95: SkillsMetric<Double>
    public let bloated: SkillsMetric<Int>
    public let share: SkillsMetric<Double>
    public let dominantSkill: String?
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        tool = try f.container.decode(String.self, forKey: .init("tool_name"))
        calls = try f.metric("call_count"); total = try f.metric("total_tokens")
        p95 = try f.metric("p95_tokens"); bloated = try f.metric("bloated_call_count")
        share = try f.metric("share_pct"); dominantSkill = try f.value("dominant_skill")
    }
}

public struct SkillsDailyObservation: Decodable, Sendable, Equatable {
    public let day: String
    public let source: String
    public let skill: String
    public let count: Int?
    public let sessions: Int?
    public let metadata: SkillsObservationMetadata
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        day = try f.container.decode(String.self, forKey: .init("day"))
        source = try f.container.decode(String.self, forKey: .init("source"))
        skill = try f.container.decode(String.self, forKey: .init("skill"))
        count = try f.value("n"); sessions = try f.value("sessions")
    }
}

public struct SkillsRoiDiagnostics: Decodable, Sendable, Equatable {
    public let pins: SkillsPinHealth?
    public let gates: SkillsGateHealth?
    public let audit: SkillsAuditHealth?
    public let usage: SkillsUsagePopulation?
    public let scripts: [SkillsUsageRow]
    public let disclosure: [SkillsDisclosureRow]
    public let churn: [SkillsChurnRow]
    public let escapes: [SkillsEscapeRow]
    public let ranking: [SkillsUsageRow]
    public let context: SkillsContextHealth?
    public let tools: [SkillsToolBurnRow]
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder)
        pins = try f.value("S1_pin_drift"); gates = try f.value("S2_gate_catch")
        audit = try f.value("S3_skill_health"); usage = try f.value("S4_usage_and_r1")
        scripts = try f.value("S6_load_vs_script") ?? []; disclosure = try f.value("S7_disclosure_funnel") ?? []
        churn = try f.value("S8_post_skill_churn") ?? []; escapes = try f.value("S9_escape_attribution") ?? []
        ranking = try f.value("S10_skill_roi_ranking") ?? []; context = try f.value("S11_context_composition")
        tools = try f.value("S12_tool_context_burn") ?? []
    }

    /// Join only the same skill across the canonical diagnostic populations; daily
    /// attribution/tool/slash populations deliberately remain separate below.
    public var usageRows: [SkillsUsageRow] {
        let ranked = ranking.isEmpty ? (usage?.top ?? []) : ranking
        let names = Set(ranked.map(\.skill))
        return ranked + scripts.filter { !names.contains($0.skill) }
    }
}

public struct SkillsRoiReport: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata
    public let diagnostics: SkillsRoiDiagnostics
    public let skillsDaily: [SkillsDailyObservation]
    public let errors: [String]
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        diagnostics = try f.value("diagnostics") ?? SkillsRoiDiagnostics(from: decoder)
        skillsDaily = try f.value("skills_daily") ?? []; errors = try f.value("errors") ?? []
    }
}

extension SkillsPinHealth: SkillsObjectPopulation {}
extension SkillsGateHealth: SkillsObjectPopulation {}
extension SkillsAuditHealth: SkillsObjectPopulation {}
extension SkillsUsagePopulation: SkillsObjectPopulation {}
extension SkillsContextHealth: SkillsObjectPopulation {}
extension SkillsUsageRow: SkillsObjectPopulation {}
extension SkillsDisclosureRow: SkillsObjectPopulation {}
extension SkillsChurnRow: SkillsObjectPopulation {}
extension SkillsEscapeRow: SkillsObjectPopulation {}
extension SkillsContextSlice: SkillsObjectPopulation {}
extension SkillsToolBurnRow: SkillsObjectPopulation {}
#endif
