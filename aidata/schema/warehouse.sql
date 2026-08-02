-- warehouse.db schema — L3 merge layer.
-- Three-grain star schema. Honestly models three grains + imperfect keys;
-- does NOT flatten into one wide table. memory_* sources are NOT here (they
-- stop at L2 and are queried directly).
--
-- CST day bucketing (ADR-22) — every timestamped fact carries a STORED
-- generated column `cst_day` (plus a second one where a table has two
-- meaningful dates, e.g. opened vs merged). It is the SINGLE definition of
-- "which CST day did this happen on"; L4 queries GROUP BY / filter on it
-- rather than re-deriving `date(..., '+8 hours')` inline.
--
-- Why a column and not a shared dim_date: the underlying timestamps are
-- physically heterogeneous — epoch-ms integers (fact_request), ISO-Z text
-- (fact_turn/fact_task), and ISO-with-offset text (fact_ado_pr). Joining a
-- calendar table would still require writing the +8h conversion on each side,
-- so it would not remove the duplication; a generated column does, and it can
-- be indexed (day aggregation was a full scan + temp B-tree before).
--
-- Always `+8 hours`, NEVER `localtime` — localtime depends on the host
-- timezone, which breaks reproducibility between a manual run and 04:00 cron.

-- ---------------------------------------------------------------------------
-- fact_request — grain = one API request. Source: raven.db `requests`.
-- session_uuid is reliable ONLY for claude-cli (parsed from a JSON blob);
-- NULL for codex/multica (their raven session_id carries no conversation id).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_request (
    request_id      TEXT PRIMARY KEY,   -- raven ULID
    ts              INTEGER NOT NULL,   -- epoch ms
    client          TEXT,               -- bare client, split from client_name
    version         TEXT,               -- version, split from client_name
    model           TEXT,
    model_canon     TEXT,               -- canonical model id (derived; original model preserved)
    resolved_model  TEXT,
    input_tokens    INTEGER,
    output_tokens   INTEGER,
    cache_read      INTEGER,
    cache_write     INTEGER,
    total_tokens    INTEGER,
    latency_ms      INTEGER,
    ttft_ms         INTEGER,
    status          TEXT,
    cost_usd        REAL,               -- derived via dim_model; NULL if tokens NULL
    session_uuid    TEXT,               -- reliable for claude-cli only
    has_session     INTEGER NOT NULL DEFAULT 0,
    tool_call_count INTEGER,            -- DEPRECATED: uniformly 0 in raven, do not use
    -- CST calendar day of `ts` (epoch ms). See the header note on CST bucketing.
    cst_day         TEXT GENERATED ALWAYS AS
                    (date(ts/1000, 'unixepoch', '+8 hours')) STORED
);
CREATE INDEX IF NOT EXISTS idx_req_ts ON fact_request(ts);
CREATE INDEX IF NOT EXISTS idx_req_client ON fact_request(client);
CREATE INDEX IF NOT EXISTS idx_req_session ON fact_request(session_uuid);
CREATE INDEX IF NOT EXISTS idx_req_model_canon ON fact_request(model_canon);
CREATE INDEX IF NOT EXISTS idx_req_cst_day ON fact_request(cst_day);

-- ---------------------------------------------------------------------------
-- fact_turn — grain = one conversation turn. Source: claude jsonl assistant lines.
-- session_id comes from camelCase `sessionId` (= filename). parent_session_id
-- from snake_case `session_id` (resume/fork lineage — different value!).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_turn (
    turn_uuid           TEXT PRIMARY KEY,
    session_id          TEXT NOT NULL,      -- from sessionId (current session)
    parent_session_id   TEXT,               -- from session_id (lineage)
    ts                  TEXT,
    project             TEXT,
    git_branch          TEXT,
    role                TEXT,
    model               TEXT,
    attribution_skill   TEXT,               -- which skill drove the turn (ROI)
    input_tokens        INTEGER,
    output_tokens       INTEGER,
    cache_read          INTEGER,
    cache_creation      INTEGER,
    tool_calls          TEXT,               -- JSON array of tool names
    finish_reason       TEXT,               -- message.stop_reason: end_turn/tool_use/max_tokens (quality signal; max_tokens = truncated). NULL on streaming/control frames.
    -- CST calendar day of `ts` (ISO-Z text). See the header note on CST bucketing.
    cst_day             TEXT GENERATED ALWAYS AS
                        (date(ts, '+8 hours')) STORED
);
CREATE INDEX IF NOT EXISTS idx_turn_session ON fact_turn(session_id);
CREATE INDEX IF NOT EXISTS idx_turn_cst_day ON fact_turn(cst_day);

-- ---------------------------------------------------------------------------
-- fact_issue — grain = one Multica issue. `issue_number` is the time-ordered
-- primary axis (monotonic with created_at; sparse/non-contiguous).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_issue (
    issue_id        TEXT PRIMARY KEY,   -- UUID
    issue_number    INTEGER NOT NULL,   -- ordering key
    identifier      TEXT,               -- MY-#### / ABC-###
    title           TEXT,
    status          TEXT,
    priority        TEXT,
    created_at      TEXT,
    workspace_id    TEXT,
    updated_at      TEXT,               -- ISO text; last edit (EXT-3). "今日完成" ≈ updated_at CST-day & status=done
    project_id      TEXT,               -- often NULL (workspace-level); degrade to per-workspace (EXT-1/ADR-22)
    -- CST calendar day of `updated_at` — the axis "完成 issue（近似）" buckets on.
    -- APPROXIMATE by nature: updated_at moves on ANY edit, not only completion (ADR-19).
    cst_day         TEXT GENERATED ALWAYS AS
                    (date(updated_at, '+8 hours')) STORED
);
CREATE INDEX IF NOT EXISTS idx_issue_number ON fact_issue(issue_number);
CREATE INDEX IF NOT EXISTS idx_issue_updated ON fact_issue(updated_at);
CREATE INDEX IF NOT EXISTS idx_issue_cst_day ON fact_issue(cst_day);
CREATE INDEX IF NOT EXISTS idx_issue_workspace ON fact_issue(workspace_id);

-- ---------------------------------------------------------------------------
-- fact_task — grain = one agent run / background job.
-- Source: multica runs + claude jobs. multica runs DO carry tokens
-- (499/508 populated, ~2.54B total — the warehouse's richest cost signal);
-- claude jobs carry cumulative `tokens`.
--
-- MIXED GRAIN — the two sources are NOT symmetric, and the asymmetry is large
-- enough to change what a query means (measured):
--   multica_run  ~12,143 rows — 100% carry issue_id, 786 carry `error`
--   claude_job       ~21 rows —   0% carry issue_id,   0 carry `error`
-- So any analysis grouping by issue_id or reading `error` describes multica_run
-- ALONE, even without an explicit `source` filter. Say so in the query comment
-- when that is the intent; add `WHERE source = 'multica_run'` when it is not.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_task (
    task_id         TEXT PRIMARY KEY,
    source          TEXT NOT NULL,      -- 'multica_run' | 'claude_job'
    issue_id        TEXT,               -- FK to fact_issue (multica runs)
    ts_start        TEXT,
    ts_end          TEXT,
    status          TEXT,
    attempt         INTEGER,
    max_attempts    INTEGER,
    tokens          INTEGER,            -- multica_run (richest signal) + claude_job; see block comment
    agent_id        TEXT,
    -- HONEST KEY (measured): resolves to fact_request.session_uuid on only ~13%
    -- of rows — the runtime records a usable session id only where it routed as
    -- claude-cli. Do NOT write an analysis that assumes this joins; anything
    -- built on it describes that 13% slice, not all tasks.
    session_id      TEXT,
    -- HONEST KEY (measured): resolves to fact_pr on ~0.03% of rows (4 of 12k).
    -- fact_pr itself holds 6 rows because its source (pr_cache reading
    -- ~/.claude/gh-pr-status-cache.json) covers almost nothing. This bridge is
    -- effectively dead — treat it as absent until pr_cache coverage improves.
    pr_url          TEXT,
    error           TEXT,               -- failure/STUCK root-cause text (multica_run); NULL for claude_job. Multi-line for codex stacktraces — classify by prefix in L4.
    trigger_summary TEXT,               -- what kicked off the run: contains "[@Role](...)" mentions (multica_run); NULL for claude_job. Drives rework-sequence signals.
    -- CST calendar day of `ts_start` (ISO-Z text). See the header note on CST bucketing.
    cst_day         TEXT GENERATED ALWAYS AS
                    (date(ts_start, '+8 hours')) STORED
);
CREATE INDEX IF NOT EXISTS idx_task_issue ON fact_task(issue_id);
CREATE INDEX IF NOT EXISTS idx_task_session ON fact_task(session_id);
CREATE INDEX IF NOT EXISTS idx_task_cst_day ON fact_task(cst_day);

-- ---------------------------------------------------------------------------
-- fact_pr — grain = one PR. Source: gh-pr-status-cache + job children[].
-- Keyed by URL (the only join available; fragile but honest).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_pr (
    pr_url          TEXT PRIMARY KEY,
    number          INTEGER,
    title           TEXT,
    state           TEXT,
    checks_passed   INTEGER,
    checks_failed   INTEGER,
    checks_pending  INTEGER,
    additions       INTEGER,
    deletions       INTEGER
);

-- ---------------------------------------------------------------------------
-- fact_ado_pr — grain = one Azure DevOps pull request I created.
-- SEPARATE from fact_pr (GitHub): ADO schema differs (reviewers/vote/draft/
-- age/branches), so we do NOT force-merge the two (ADR-13). Creator is filtered
-- to my immutable ADO-native id upstream (ADR-22). created_date/closed_date are
-- ISO-8601 text (bucket with date(col,'+8 hours'), not epoch).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_ado_pr (
    pr_id           INTEGER PRIMARY KEY,
    title           TEXT,
    status          TEXT,               -- active | completed | abandoned
    created_date    TEXT,               -- ISO text
    closed_date     TEXT,               -- ISO text; set when completed/abandoned
    creator_id      TEXT,               -- immutable ADO Server descriptor
    source_branch   TEXT,
    target_branch   TEXT,
    is_draft        INTEGER,            -- 0/1
    reviewers       TEXT,               -- JSON array of {name, vote}
    age_hours       REAL,               -- age at normalize time
    repo            TEXT,
    -- Two CST days: opened (created_date) and closed (closed_date). Both are
    -- needed because the daily PR trend counts opens and merges separately.
    cst_day         TEXT GENERATED ALWAYS AS
                    (date(created_date, '+8 hours')) STORED,
    cst_closed_day  TEXT GENERATED ALWAYS AS
                    (date(closed_date, '+8 hours')) STORED
);
CREATE INDEX IF NOT EXISTS idx_ado_pr_cst_day ON fact_ado_pr(cst_day);
CREATE INDEX IF NOT EXISTS idx_ado_pr_cst_closed ON fact_ado_pr(cst_closed_day);
CREATE INDEX IF NOT EXISTS idx_ado_pr_created ON fact_ado_pr(created_date);

-- ---------------------------------------------------------------------------
-- fact_repo_snapshot — grain = one GitHub repo on one CST day. Source: the
-- github_repo adapter (curated tool-radar watchlist). Composite PK gives an
-- idempotent one-row-per-repo-per-day snapshot; star deltas are derived in the
-- L4 radar query via a correlated subquery over snapshot_date (serve.py runs on
-- stdlib sqlite 3.19, which predates window functions). snapshot_date is stamped as the
-- CST calendar day at collect time (already bucketed — no +8h needed here).
-- provenance reserves a v2 "discovered" bucket alongside today's "curated".
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_repo_snapshot (
    repo            TEXT NOT NULL,          -- "owner/name"
    snapshot_date   TEXT NOT NULL,          -- CST "YYYY-MM-DD"
    stars           INTEGER,
    forks           INTEGER,
    description     TEXT,
    language        TEXT,
    topics          TEXT,                   -- JSON array of topic strings
    pushed_at       TEXT,                   -- ISO text; last push to the repo
    provenance      TEXT DEFAULT 'curated', -- curated | discovered (v2)
    PRIMARY KEY (repo, snapshot_date)
);
CREATE INDEX IF NOT EXISTS idx_repo_snap_date ON fact_repo_snapshot(snapshot_date);

-- ---------------------------------------------------------------------------
-- fact_github_pr — grain = one GitHub pull request I created (across the repos
-- in GITHUB_PR_REPOS). SEPARATE from fact_ado_pr (Azure DevOps) and fact_pr,
-- mirroring ADR-13's "one table per PR provenance": GitHub's shape (state /
-- merged_at / url) differs from ADO's. Composite PK (repo, pr_number) keeps a
-- PR number that repeats across repos distinct. created_date/merged_date are
-- ISO-8601 text (bucket with date(col,'+8 hours'), not epoch). Feeds the digest
-- "开了 N 个 PR（合并 N 个）" line, unioned with fact_ado_pr.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_github_pr (
    repo            TEXT NOT NULL,          -- "owner/name"
    pr_number       INTEGER NOT NULL,
    title           TEXT,
    state           TEXT,                   -- OPEN | MERGED | CLOSED
    created_date    TEXT,                   -- ISO text
    merged_date     TEXT,                   -- ISO text; set when merged
    closed_date     TEXT,                   -- ISO text; set when closed/merged
    url             TEXT,
    is_draft        INTEGER,                -- 0/1
    -- Two CST days: opened (created_date) and merged (merged_date), mirroring
    -- fact_ado_pr. Note the ADO twin uses closed_date + status='completed' for
    -- its merge signal; GitHub has an explicit merged_date, so no status filter.
    cst_day         TEXT GENERATED ALWAYS AS
                    (date(created_date, '+8 hours')) STORED,
    cst_merged_day  TEXT GENERATED ALWAYS AS
                    (date(merged_date, '+8 hours')) STORED,
    PRIMARY KEY (repo, pr_number)
);
CREATE INDEX IF NOT EXISTS idx_github_pr_created ON fact_github_pr(created_date);
CREATE INDEX IF NOT EXISTS idx_github_pr_cst_day ON fact_github_pr(cst_day);
CREATE INDEX IF NOT EXISTS idx_github_pr_cst_merged ON fact_github_pr(cst_merged_day);

-- ---------------------------------------------------------------------------
-- dim_model — price map for cost derivation (raven/claude carry no cost).
-- USD per 1M tokens. Loaded from schema/dim_model.csv.
--
-- SCD Type 1 (overwrite, no history). Cost is derived ONCE at L2 by
-- adapters/raven.py::_cost() and stored in fact_request.cost_usd, so editing a
-- price does NOT retroactively change history — UNLESS you re-run
-- `normalize --source raven`, which silently reprices every historical row at
-- today's rates. If you need historical fidelity after a price change, do not
-- re-normalize raven; add the model as a new row instead.
--
-- Related: `cli.py merge` alone will NOT pick up a price edit — L3 only copies
-- cost_usd from L2. Run `normalize --source raven` first (the sentinel for a
-- missed price is test_warehouse_integrity::test_no_tokens_without_cost).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_model (
    model               TEXT PRIMARY KEY,
    input_per_mtok      REAL,
    output_per_mtok     REAL,
    cache_read_per_mtok REAL,
    cache_write_per_mtok REAL
);

-- ---------------------------------------------------------------------------
-- dim_session — per-session rollup (populated during merge from facts).
--
-- NAMED `dim_`, BUT IT IS A DERIVED FACT, not a conformed dimension. It carries
-- additive measures (request_count / total_tokens / total_cost_usd) aggregated
-- FROM fact_request, rather than descriptive attributes of an independent
-- entity. Two consequences worth knowing before building on it:
--   - It is 100% claude-cli (measured): fact_request.session_uuid is only
--     resolvable for that client, so this covers one slice of traffic, not all.
--   - Its measures must never be joined onto fact_request and re-summed —
--     that double-counts. Read it standalone (behavior/runaway-sessions does).
-- The name is kept for compatibility; treat it as `dws_session` conceptually.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_session (
    session_id      TEXT PRIMARY KEY,
    first_ts        INTEGER,
    last_ts         INTEGER,
    request_count   INTEGER,
    total_tokens    INTEGER,
    total_cost_usd  REAL,
    client          TEXT
);
