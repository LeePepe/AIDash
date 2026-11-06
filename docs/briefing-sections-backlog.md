# Briefing sections backlog

This document is the preservation contract for briefing content intentionally
hidden by the simplified default publication path.

## Publication policy

`build_briefing()` still constructs the upstream candidates
(`aidata/L5_apps/digest/aidash.py:1621-1735`), but the default publication gate
must expose exactly `10 · 总览` and `30 · 今日规划`. The budget stage is not a
permission to revive a deferred candidate.

Deferred means **gated, not deleted**:

- Keep every producer, source query, freshness check, payload shape, and
  degrade-safe omission rule available for a later redesign.
- Do not move content generation into the app or replace real data with
  placeholders.
- Healthy or merely stale delivery is silent. Only a genuinely failed or
  degraded delivery may become one concise warning inside `总览`; it is never
  a separate default container.
- A future redesign must pass the entry's data, freshness, duplication, and
  acceptance gates below before re-enabling publication.

## Inventory

Each deferred title appears once here. The detailed entries use stable IDs so
the exact titles do not drift when the catalog is revised.

| ID | Deferred title | Current generator |
|---|---|---|
| B01 | 昨日汇总 | `_prose_containers()` |
| B02 | 今日工作 | `_work_container()` |
| B03 | 24h 证据时间线 | `_hourly_timeline_container()` |
| B04 | 成本归因 | `_attribution_container()` |
| B05 | 交叉信号 | `_relationship_container()` |
| B06 | AI 效能 | `_ai_efficiency_container()` |
| B07 | 时间与产出 | `_time_output_container()` |
| B08 | 工程与编排图表 | `_retro_ops_container()` |
| B09 | 可改良 | `_prose_containers()` plus `_model_tier_card()` |
| B10 | GitHub 工具雷达 | `_radar_containers()` |
| B11 | 卡型兴趣 | `_card_interest_container()` |
| B12 | 新闻雷达 | `_news_container()` |
| B13 | 数据源健康 | `_overview_container()` / `render.py` health line |
| B14 | 日报投递健康 | `_overview_container()` delivery warning |

## Deferred-entry contracts

### B01 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:677-690`,
  `_prose_containers()`.
- **Data:** `full_md` is parsed into Markdown sections; the prose builder
  consumes the corresponding section through `_section()` and `_lines_body()`.
  The same source also feeds the overview section helper at
  `aidata/L5_apps/digest/aidash.py:535-573`.
- **Why deferred:** the content duplicates the overview's digest prose and
  makes the default page compete with the focused action plan.
- **Preserve:** keep Markdown parsing, ordering, line cleanup, source health
  behavior, and omission when the section is absent. Do not delete the source
  section or turn its absence into an empty card.
- **Redesign gate:** publish only after a design proves a distinct reading job,
  removes overlap with the concise overview body, defines a freshness window,
  and specifies a bounded card shape with wrapping and no numeric truncation.
- **Test handoff:** rewrite the generic insight and old hero assumptions in
  `aidata/tests/test_aidash_payload.py:112-120,201-223` and the page-band
  assumptions in `aidata/tests/test_digest_aidash.py:101-114`.

### B02 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:737-762`,
  `_work_container()`.
- **Data:** `sources.work_by_project`; healthy project bundles become one
  wide `metric` card, capped at six projects. Missing or degraded work data
  omits the candidate.
- **Why deferred:** it is a retrospective activity view, not a current
  action. Showing it beside the retained plan spends the first screen on
  activity that may not change a user's next decision.
- **Preserve:** retain per-project grouping, neutral semantics
  (`higherIsBetter: false`), session/output context, descending source order,
  six-project cap, and degrade-safe omission.
- **Redesign gate:** define how retrospective activity differs from actionable
  planning, require a bounded reporting window and source timestamp, and
  prove that the card does not duplicate cost, efficiency, or timeline views.
- **Test handoff:** map `aidata/tests/test_work_by_project_card.py:17-62` and
  the old publication clauses in `aidata/tests/test_aidash_payload.py:317-340`
  to the future work-activity owner.

### B03 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:765-803`,
  `_hourly_timeline_container()`.
- **Data:** `sources.hourly_timeline`; it requires a healthy bundle, exactly
  24 buckets, and at least one active evidence bucket. Payload data includes
  summaries, evidence IDs, citations, and up to three next steps.
- **Why deferred:** a full-day evidence trace is valuable for investigation
  but too dense for the default five-minute briefing.
- **Preserve:** retain the 24-bucket requirement, active-evidence guard,
  citation links, sampled markers, next-step cap, date/title derivation, and
  omission on degraded or empty input.
- **Redesign gate:** specify timezone/date semantics, evidence identity and
  privacy boundaries, citation behavior, loading/empty/error states, and a
  compact interaction that does not fabricate zero activity.
- **Test handoff:** preserve producer/freshness coverage while rewriting
  default-publication expectations in
  `aidata/tests/test_hourly_timeline_and_bridge.py:22-25,78-82`.

### B04 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:1059-1101`,
  `_attribution_container()`.
- **Data:** `sources.cost_by_project`, `model_by_project`, `leverage`, and
  `rework_by_workspace`; the builder emits project/model/workspace `barList`
  cards plus the typed-input leverage metric when each source is healthy.
- **Why deferred:** attribution is explanatory detail, not the retained
  high-signal cost KPI. Publishing it by default also activates provider
  coupling and row-level deduplication.
- **Preserve:** keep numeric payloads, project/model/workspace dimensions,
  coverage and residual totals, leverage units, health guards, and the
  post-budget cost-row dedup contract in
  `aidata/L5_apps/digest/aidash.py:451-460,474-532`.
- **Redesign gate:** require an explicit attribution coverage threshold,
  residual treatment, stable project/model identity rules, no double counting,
  and a clear relationship to the retained `成本` KPI. Low coverage must
  degrade honestly rather than imply complete attribution.
- **Test handoff:** preserve provider tests but remove placement/survival
  assumptions in `aidata/tests/test_cost_attribution.py:115-119,183-187,201-205,228-232,251-255,313-327`,
  `aidata/tests/test_briefing_budget.py:541-548,620-647,650-701,714-733,736-756`,
  and re-scope `aidata/tests/test_metric_dedup.py:33-182`.

### B05 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:1363-1437`,
  `_relationship_container()`.
- **Data:** `sources.rework_relationship` supplies a workspace × root-cause
  matrix; `sources.retro_ops.ci_points` supplies the fallback repository
  volume × observed-pass-rate scatter. Both use a relationship card and
  observation-only summaries.
- **Why deferred:** relationship visualizations require context and can be
  mistaken for causal claims when shown without the surrounding methodology.
- **Preserve:** retain the 2×2 matrix guard, sample-size requirement, fallback
  point guard, time window, metric definition, and explicit
  “correlation is not causation” wording.
- **Redesign gate:** require at least two meaningful axes, a stated sample and
  time window, denominator definitions, accessible labels, and acceptance
  tests that reject ranking data disguised as a relationship.
- **Test handoff:** map the relationship slot and budget-survival clauses in
  `aidata/tests/test_digest_aidash.py:246-250` and
  `aidata/tests/test_briefing_budget.py:501-538,759-780,871-881`.

### B06 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:968-1028`,
  `_ai_efficiency_container()`.
- **Data:** `sources.ai_efficiency` provides cache-hit and rework series,
  failure ranks, session-quality segments, and planner-gap counts;
  `sources.tool_cross` provides tool-cost ranking. Each card is emitted only
  for healthy, non-empty data.
- **Why deferred:** the section combines several diagnostic dimensions and
  needs explanatory context before a reader can act on it.
- **Preserve:** retain series ordering/trend calculation, units,
  higher-is-better semantics, warning-only planner-gap behavior, source
  health checks, and omission of empty cards/containers.
- **Redesign gate:** define denominators and time windows for every metric,
  distinguish observation from causation, provide actionable thresholds, and
  keep the card set bounded without hiding a degraded source.
- **Test handoff:** preserve producer contracts but remove default-publication
  expectations from `aidata/tests/test_batch2_cards.py:80-148`.

### B07 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:1104-1116`,
  `_time_output_container()`.
- **Data:** `sources.app_focus` and `sources.commit_by_repo`; each healthy,
  non-empty rank bundle becomes a `barList` card in one container.
- **Why deferred:** app focus and repository output are retrospective
  productivity detail, with no default action unless their time basis and
  interpretation are explicit.
- **Preserve:** retain independent source bundles, source ordering, neutral
  ranking semantics, and omission when neither bundle is usable.
- **Redesign gate:** define the reporting interval, timezone, repository
  identity, treatment of non-code output, and a user-visible distinction
  between activity and value.
- **Test handoff:** map the composition and deferred-publication clauses in
  `aidata/tests/test_batch2_cards.py:151-179`.

### B08 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:1131-1240`,
  `_retro_ops_container()`.
- **Data:** `sources.retro_ops` supplies CI/GTT distributions, repository
  rankings, release/workspace operational bars, PR-monitor statistics,
  Claude-job states, and agent summaries; `sources.multica` may add completed
  issue statistics.
- **Why deferred:** this is an operational cockpit with many signals and
  implementation-specific vocabulary, not a concise user briefing.
- **Preserve:** retain leading/trailing card grouping, the operational
  section header, health/empty guards, bounded completed items and stats, and
  neutral source-derived values. Do not delete the underlying CI/GTT/PR
  monitor producers.
- **Redesign gate:** define the intended operator audience, stable time
  windows, source freshness, privacy-safe identifiers, and a card budget that
  keeps CI, orchestration, and release signals understandable separately.
- **Test handoff:** rewrite publication expectations while retaining builder
  coverage in `aidata/tests/test_aidash_payload.py:344-439` and
  `aidata/tests/test_digest_aidash.py:118-214`.

### B09 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:710-733`,
  `_prose_containers()`; the same builder receives the model-tier card
  produced upstream.
- **Data:** Markdown improvement lines plus `sources.cost_improvement`,
  `value_efficiency`, and `model_tier`; the builder orders efficiency,
  cost, Markdown, then model-tier cards and omits the container when empty.
- **Why deferred:** recommendations mix prose, cost interpretation, and
  model distribution; without a redesign they duplicate attribution and
  efficiency diagnostics and can sound prescriptive without an action path.
- **Preserve:** retain provider calculations, ordering, model-tier segments,
  health checks, Markdown parsing, and omission of empty cards. Preserve
  recommendation text as agent-authored content; the app must not generate
  or summarize it.
- **Redesign gate:** every recommendation must identify evidence, expected
  benefit, confidence, and a safe next action; cost and efficiency must use
  compatible denominators and time windows; no zero or degraded provider may
  become an invented improvement.
- **Test handoff:** map `aidata/tests/test_batch2_cards.py:210-227`,
  `aidata/tests/test_cost_improvement_card.py:66-91`, and
  `aidata/tests/test_value_efficiency_card.py:62-82` to the future
  recommendation owner.

### B10 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:844-873`,
  `_radar_containers()`.
- **Data:** `sources.repo_radar`; healthy repository cards are star-ordered,
  preference-adjusted, split into the `now` and `horizon` tiers, and rendered
  as `trending` cards with repository URL, stars, delta, category, and reason.
- **Why deferred:** an external watchlist is exploratory content and should
  not displace the daily operational summary.
- **Preserve:** retain tier ordering, preference application, source health
  guard, URL and repository metadata, and omission when no tier has data.
- **Redesign gate:** require freshness and deduplication rules, safe/valid
  external links, a bounded item count, explainable tier membership, and
  acceptance coverage for empty/degraded radar data.
- **Test handoff:** rewrite publication assumptions in
  `aidata/tests/test_aidash_radar.py:31-46,74-85,105-113`.

### B11 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:1310-1327`,
  `_card_interest_container()`.
- **Data:** `sources.card_interest`; `_card_interest_body()` consumes
  descending whole-card-star counts and emits a Top-N `insight` body only
  when the source is healthy and non-empty.
- **Why deferred:** this is a personalization/feedback view, not briefing
  content required to understand today's work.
- **Preserve:** retain the append-only user-event interpretation, card-type
  ordering and deterministic tie-break, Top-N cap, health guard, and omission
  for no signal. Do not infer preferences from unapproved telemetry.
- **Redesign gate:** define minimum sample size, privacy boundaries, time
  window, deterministic ties, and an explanation of how the ranking changes
  future agent-authored content without app-side authoring.
- **Test handoff:** rewrite default-publication expectations in
  `aidata/tests/test_card_interest_card.py:91-112` and the named-slot
  assumptions in `aidata/tests/test_briefing_budget.py:978-995`.

### B12 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:1254-1280`,
  `_news_container()`.
- **Data:** `sources.news_radar`; healthy headlines are grouped by topic,
  rendered in a stable topic order, and emitted as one wide `trending` card
  per topic with title, URL, score, and category.
- **Why deferred:** news is exploratory and time-sensitive; it needs a
  stronger freshness, relevance, and deduplication contract than the default
  briefing currently provides.
- **Preserve:** retain topic labels, stable ordering, source URLs, omission
  on degraded/empty input, and the distinction between source content and
  agent-authored briefing text.
- **Redesign gate:** require publication timestamps or an equivalent freshness
  marker, URL validation, duplicate-story handling, topic fallback behavior,
  and a bounded card/item budget.
- **Test handoff:** map composition clauses in
  `aidata/tests/test_batch2_cards.py:181-207`.

### B13 — Generator and data contract

- **Generator:** overview insertion at
  `aidata/L5_apps/digest/aidash.py:600-604`; source-health extraction at
  `aidata/L5_apps/digest/aidash.py:227-231`; source line generation at
  `aidata/L5_apps/digest/render.py:45-59,203-225`; template wiring at
  `aidata/L5_apps/digest/app.py:151-157`.
- **Data:** the Markdown preamble carries raven, optional multica, ADO, and
  state.db status through the render health line.
- **Why deferred:** source diagnostics are implementation telemetry, not
  glanceable briefing content. The old path can also expose a legacy
  `multica✅` signal, which is not an allowed default overview card.
- **Preserve:** keep source health computation, degradation annotations,
  render-time provenance, and best-effort digest production. Removing this
  card from default publication must not remove source freshness checks.
- **Redesign gate:** create an explicitly diagnostic surface with per-source
  freshness, severity, remediation ownership, and a clear distinction between
  missing, stale, skipped, and failed. Default overview tests must continue to
  reject this card.
- **Test handoff:** remove the source-health half of
  `aidata/tests/test_aidash_payload.py:234-243` and rewrite the health-card
  assumptions in `aidata/tests/test_delivery_health.py:60-87`.

### B14 — Generator and data contract

- **Generator:** `aidata/L5_apps/digest/aidash.py:605-613`,
  `_overview_container()` and `delivery_health_line()`.
- **Data:** persisted `DeliveryState`; the warning is eligible only when the
  last push failed or the persisted delivery is genuinely stale.
- **Why deferred:** healthy and merely stale delivery should not add noise to
  the briefing. A real failure is exceptional and belongs as one concise
  inline signal, not as a new default container.
- **Preserve:** retain best-effort push semantics, failure/staleness
  distinction, neutral degradation text, and the ability to surface one
  concise warning inside `总览`. Do not turn delivery status into a second
  health card or silently suppress a genuine failure.
- **Redesign gate:** define stale thresholds and timestamp authority, test
  failed/stale/healthy cases separately, cap the warning to one overview
  signal, and verify that no healthy or merely stale state is published.
- **Test handoff:** rewrite `aidata/tests/test_delivery_health.py:60-87,90-128`
  around degraded-only inline behavior.

## Crosswalk for future test rewrites

The following legacy clauses are preserved as contracts to migrate, not
permission to delete their producers:

- **Overview and prose:** `aidata/tests/test_aidash_payload.py:90-101,112-120,201-223,234-243,317-340,344-439`;
  `aidata/tests/test_digest_aidash.py:101-114,118-214,246-250`.
- **Budget and provider selection:** `aidata/tests/test_briefing_budget.py:99-107,155-176,364-390,501-538,541-548,620-647,650-701,714-733,736-756,759-780,871-881,978-995`.
- **Batch-2 producers:** `aidata/tests/test_batch2_cards.py:80-148,151-179,181-207,210-227`.
- **Radar, interest, cost, and activity:** `aidata/tests/test_aidash_radar.py:31-46,74-85,105-113`;
  `aidata/tests/test_card_interest_card.py:91-112`;
  `aidata/tests/test_cost_attribution.py:115-119,183-187,201-205,228-232,251-255,313-327`;
  `aidata/tests/test_cost_improvement_card.py:66-91`;
  `aidata/tests/test_value_efficiency_card.py:62-82`;
  `aidata/tests/test_work_by_project_card.py:17-62`.
- **Timeline and derived rows:** `aidata/tests/test_hourly_timeline_and_bridge.py:22-25,78-82`;
  `aidata/tests/test_metric_dedup.py:33-182`;
  `aidata/tests/test_todo_truncation.py:296-350`;
  `aidata/tests/test_inbox.py:37-173`.

Each rewrite must assert both sides of the contract: the corresponding
producer remains available for a future redesign, while the default
`build_briefing()` result remains exactly the two-container publication.
