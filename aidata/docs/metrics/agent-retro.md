# Agent-Retro 6-Layer Trajectory & Horizon Contracts

The `agent-retro` pipeline is an opt-in, privacy-safe extension of `aidata` across L1–L5 for 6-layer multi-agent trajectory health, long-horizon waste (`L-Horizon`), and per-skill `vN@sha` `post_fix` watermarks. It prepares backward-compatible snapshot fields for `AIDashApp` (Gate 4 Data-Before-UI) without auto-enabling scheduled cron collection.

## Locked Contracts & Boundaries

- **Skill Registry**: `agent-retro` is registered in `quality_contracts.py` (`ACTIVE_SKILLS`), `L4_serve/queries/retro/skill_roi_diagnostics.sql` (`valid_skills`), and `L5_apps/digest/skills_roi_snapshot.py` (`_CANONICAL_SKILL_ALLOWLIST`).
- **Opt-In L1/L2 Projection (`adapters/agent_retro.py`)**: Exposes `normalize_records(records, *, db_path=None)` and `collect(*, now=None)` to materialize `clean/agent_retro.db` (`retro_finding` and `horizon_waste` tables). It is excluded from `config.SOURCES` and `SCHEDULED_SOURCES`.
- **Privacy & Redaction**: Only closed enums, counts, durations, `vN@sha` skill versions, and SHA-256 hashes are persisted. Raw prompt text, session transcripts, and secret-bearing local paths are stripped before persistence.
- **L3 Warehouse Facts (`schema/warehouse.sql` + `merge.py`)**:
  - `fact_agent_retro_finding`: `(finding_uid, source, session_id, goal_id, role_key, skill, layer_key, finding_code, severity, skill_version, is_post_fix, occurrence_count, ts, cst_day)` where `layer_key` is in `role|handoff|invoke|exec|friction|horizon` and `cst_day` is a `STORED` generated column using `date(ts, '+8 hours')`.
  - `fact_agent_horizon_waste`: `(waste_uid, source, session_id, role_key, skill, horizon_code, category_key, wasted_turns, wasted_tokens, duration_sec, ts, cst_day)` with `cst_day` `STORED` `+8 hours`.
  - `merge.py` commits open SQLite transactions before `DETACH DATABASE`.
- **L4 Exploratory Queries (`L4_serve/queries/retro/`)**:
  - `agent_retro_six_layer.sql` (`-- aidata-tier: explore`): Rolling CST window aggregation of 6-layer pre-fix vs post-fix anomaly counts and role/skill attributions.
  - `agent_horizon_waste.sql` (`-- aidata-tier: explore`): Rolling CST window aggregation of long-horizon wasted turns, wasted tokens, and duration by category/role/skill.
- **L5 Plain-Language Snapshots (`L5_apps/digest/`)**:
  - `agent_efficiency_snapshot.py` emits an additive `agent_retro` object inside `agent-efficiency.json` with explicit `coverage_status` (`missing` / `unknown` / `partial` / `healthy`), plain-language 6-layer labels (`角色边界`, `交接完整度`, `工具与参考调用`, `执行与返工收敛`, `人机协作摩擦`, `长程上下文损耗`), `horizon_waste`, and `skill_watermarks` (`vN@sha` pre-fix vs post-fix status).
  - `skills_roi_snapshot.py` enriches `skill_retro` with `agent_retro_watermarks` when available while preserving existing fallback and schema contracts.
  - Plain-language UI labels (`label_zh`, `label_en`) never expose bare internal diagnostic codes or script filenames.
