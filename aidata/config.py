"""Central config: source paths, layer dirs, layout constants.

Single source of truth for where everything lives. All paths derived from
AIDATA_HOME (this package's parent) and the user's real data locations.
Immutable module-level constants — never mutated at runtime.
"""

from __future__ import annotations

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Layer directories (inside this project)
# ---------------------------------------------------------------------------
AIDATA_HOME = Path(__file__).resolve().parent
RAW_DIR = AIDATA_HOME / "L1_collect" / "raw"
CLEAN_DIR = AIDATA_HOME / "L2_normalize" / "clean"
WAREHOUSE_DB = AIDATA_HOME / "L3_merge" / "warehouse.db"
QUERIES_DIR = AIDATA_HOME / "L4_serve" / "queries"
DIGEST_DIR = AIDATA_HOME / "L5_apps" / "digest" / "archive"
SCHEMA_DIR = AIDATA_HOME / "schema"
STATE_FILE = AIDATA_HOME / "state.json"

# ---------------------------------------------------------------------------
# External source locations (read-only). Resolved from HOME so this is portable
# across machines but grounded in the real paths found during design.
# ---------------------------------------------------------------------------
HOME = Path(os.path.expanduser("~"))

RAVEN_DB = HOME / "Library" / "Application Support" / "raven" / "raven.db"
CLAUDE_PROJECTS_DIR = HOME / ".claude" / "projects"
CLAUDE_JOBS_DIR = HOME / ".claude" / "jobs"
CLAUDE_PR_CACHE = HOME / ".claude" / "gh-pr-status-cache.json"
CLAUDE_MEMORY_DIR = (
    HOME / ".claude" / "projects" / f"-Users-{HOME.name}" / "memory"
)
HERMES_MEMORY_DB = HOME / ".hermes" / "memory_store.db"
HERMES_MEMORY_MD_DIR = HOME / ".hermes" / "memories"
MULTICA_CONFIG = HOME / ".multica" / "config.json"

# Collected-tools stockpile (save-tool skill): one Markdown note per tool, each
# carrying a github.com/owner/repo URL. This is the CURATED watchlist for the
# GitHub tool-radar source (github_repo). Scanning the folder keeps the radar
# auto-synced with the stockpile — add a repo note → it's tracked next run. Read
# -only; the adapter degrades to empty when the folder is absent (ADR-23).
# Portable default; override in config_local.py if your stockpile lives elsewhere.
COLLECTED_TOOLS_DIR = HOME / "Development" / "Personal" / "collected-tools"

# local_git source — the roots we walk for `.git` repos to aggregate MY own
# commit activity (the "coding process" GitHub PRs never capture). Scoped to
# ~/Development (NOT all of ~) so we skip huge/irrelevant trees (Library,
# node_modules elsewhere) and keep the walk fast + bounded. A tuple so more
# roots can be added; each is walked depth-limited and degrades to skip when
# absent (ADR-23). The scanned-for author email is read live from
# `git config --global user.email`, never hard-coded here.
LOCAL_GIT_SCAN_ROOTS = (
    HOME / "Development",
)

# Hermes per-session store (EXT-5, ADR-7). L2-only source (not merged): the
# digest queries its clean DB directly, like the memory_* sources.
HERMES_STATE_DB = HOME / ".hermes" / "state.db"

# Codex session logs (codex_prompts source) — one JSONL per session under a
# YYYY/MM/DD tree. L2-only. Each file's FIRST record is `session_meta`, whose
# `originator` says who drove the session: `codex-tui`/`Codex Desktop` = me at
# a keyboard, `multica-agent-sdk`/`codex_exec` = automation. That field is what
# splits the source into "my prompts" (body kept) and "machine prompts"
# (hash + prefix only) — see the adapter docstring. Degrades to 0 when absent.
CODEX_SESSIONS_DIR = HOME / ".codex" / "sessions"

# Kimi Code session logs (kimi_prompts source) — the real event log lives at
# sessions/<workdir>/<session>/agents/<agent>/wire.jsonl, where every
# `turn.prompt` carries an explicit `origin.kind` (user / system_trigger /
# injection / ...). That single field is the cleanest human-vs-machine
# discriminator of any source here. NOT `user-history/` — that is a
# shell-history-style buffer with no timestamp or session id (it does preserve
# slash commands as typed, its one advantage). L2-only; degrades to 0 when
# Kimi is not installed (ADR-23).
KIMI_SESSIONS_DIR = HOME / ".kimi-code" / "sessions"

# Chrome browsing history (browser_history source) — the local SQLite the
# browser writes visits into. L2-only source (not merged): the digest can
# query its clean DB directly for a domain-level "what did I look up / which
# AI tools did I use" signal. Read STRICTLY read-only + immutable (Chrome holds
# a lock while running; immutable=1 bypasses it — verified: a plain mode=ro open
# raises "database is locked", the immutable open reads fine, no Full Disk
# Access / TCC prompt for Chrome's own profile). Only Chrome — Safari's
# History.db needs FDA (verified: authorization denied) and is deliberately
# out of scope. Privacy red line is stricter here than any other source: urls
# may carry tokens in query strings / internal hostnames, so the adapter keeps
# only scheme://host/path (query + fragment dropped) and a redacted title
# preview, and degrades to 0 when Chrome is not installed (ADR-23).
CHROME_HISTORY_DB = (
    HOME / "Library" / "Application Support" / "Google" / "Chrome"
    / "Default" / "History"
)

# gecko screen-time tracker (gecko source) — the local SQLite the macOS menu-bar
# app writes one row per app-focus session into. L2-only source (NOT merged): the
# clean DB is queried directly for an "attention / time-allocation" signal (which
# apps held focus, for how long) — the one dimension no other L1 source captures.
# READ MODE differs from browser_history ON PURPOSE: gecko writes in WAL mode, so
# it is opened with a PLAIN mode=ro (immutable=False). An immutable open reads only
# the base file and MISSES rows still in the -wal file (verified: immutable saw an
# empty table, plain mode=ro read all live rows) — the OPPOSITE of Chrome, which
# needs immutable=1 to bypass its write lock. Privacy red line matches
# browser_history: URLs are reduced to host+path (query/fragment dropped) before
# raw/, window/tab titles are redacted, and `synced_at` is never read. Degrades to
# 0 when gecko is not installed (ADR-23).
GECKO_DB = HOME / "Library" / "Application Support" / "ai.hexly.gecko" / "gecko.sqlite"

# multica CLI binary (falls back to PATH lookup if this exact path is absent)
MULTICA_BIN = "/opt/homebrew/bin/multica"

# Models that have NO published price, and so are deliberately measured in
# TOKENS ONLY — `cost_usd` stays NULL for their rows, on purpose.
#
# Pricing is a fact, not a guess. Inventing a rate for an unpriced model would
# be strictly worse than the NULL: it turns an honest gap into a precise-looking
# wrong number that flows into every cost-attribution card and never trips a
# data-quality gate again. A NULL is visible; a fabricated dollar figure is not.
#
# `test_no_tokens_without_cost` exempts exactly these names, and a sibling test
# asserts their token counts are still populated — the exemption is about a
# MISSING PRICE, never about missing usage. Keep this list narrow: a NEW
# unpriced model SHOULD fail that gate loudly rather than quietly join the
# exempt set. Remove a name here the moment a real price is known.
UNPRICED_MODELS: tuple[str, ...] = ("gpt-5.6-terra", "gpt-5.6-luna")

# Workspaces the digest collects from (ADR-5 / EXT-2): an explicit allow-list of
# (uuid, friendly_name); the friendly name is used verbatim in the digest's
# per-workspace breakdown. Each workspace keeps its OWN watermark (ADR-19) —
# never a shared global cursor. Deliberately an allow-list, not "all workspaces":
# only the ones whose activity belongs in the personal digest are listed.
#
# Empty by default so this file carries no machine-specific identifiers; the
# real list comes from config_local.py (see the bottom of this file).
MULTICA_WORKSPACES: tuple[tuple[str, str], ...] = ()

# Window (in days) for the multica_issue updated_since re-read (ADR-19 / EXT-3).
# Re-fetching recently-updated issues catches OLD issues completed recently,
# which the old monotonic number>watermark strategy missed forever.
MULTICA_UPDATED_WINDOW_DAYS = 14

# ---------------------------------------------------------------------------
# Azure DevOps — work PR source (EXT-4, ADR-6/22).
# The tracked repo lives on an ADO *Server* instance, whose createdBy.id is a
# DIFFERENT namespace from the AAD object id returned by
# `az ad signed-in-user show` (verified 2026-07-11: the AAD id does NOT match,
# and filtering by it yields zero PRs). We therefore query by email and
# double-filter on the immutable ADO-native creator descriptor — honoring
# ADR-22's intent (filter on an immutable id, never display name) while working
# on ADO Server.
#
# Empty by default: these are per-machine, per-account identifiers and MUST NOT
# be committed. Set them in config_local.py (see the bottom of this file). With
# them unset the ado_pr source degrades to a no-op (ADR-23).
# ---------------------------------------------------------------------------
ADO_ORG = ""
ADO_PROJECT = ""
ADO_REPO = ""
ADO_CREATOR_EMAIL = ""
ADO_CREATOR_ID = ""

# GitHub PRs (github_pr source) — my personal-project PRs live on GitHub, not
# ADO. `gh pr list --author @me` is run per repo (reuses existing gh auth). The
# digest's "开了 N 个 PR" line unions these with ado_pr. A repo that errors/has
# no PRs simply contributes nothing (ADR-23).
#
# Empty by default (this repo is public — the repo list is personal). Set your
# own in config_local.py; unset ⇒ the github_pr source is a no-op.
GITHUB_PR_REPOS: tuple[str, ...] = ()

# ---------------------------------------------------------------------------
# AIDash CLI (aidash_events source) — resolves the `aidash` binary the same way
# the L5 digest push does (L5_apps/digest/aidash.resolve_aidash_bin), but kept
# here as shared constants so an L1 adapter never has to import L5 (layer
# boundary). Prefer the FIXED install (`~/.local/bin/aidash`, outside
# DerivedData) so a rebuild can't churn it; fall back to the newest DerivedData
# build (recipe glob — never `which aidash`, which the user rejects). The
# adapter degrades to a no-op when neither resolves (ADR-23).
# ---------------------------------------------------------------------------
AIDASH_BIN_FIXED = str(HOME / ".local" / "bin" / "aidash")
AIDASH_BIN_GLOB = (
    "Library/Developer/Xcode/DerivedData/"
    "AIDash-*/Build/Products/Debug/aidash"
)

# ---------------------------------------------------------------------------
# News feeds (news source) — a key-free, public, layer-through news radar.
# One maintainable list, mirroring COLLECTED_TOOLS_DIR's "config-as-manifest"
# role for github_repo: add/remove a tuple here to change coverage — collect()
# just walks this list, never hard-codes a feed inline.
#
# Each entry: (topic, kind, target, lang, geo)
#   topic   — our stable subject label (the L2 `topic` column; groups items).
#   kind    — how to fetch/parse the feed:
#               "gnews_search"  Google News keyword RSS (target = query text)
#               "gnews_topic"   Google News section RSS (target = TOPIC token)
#               "rss"           generic RSS/Atom over HTTP (target = full URL)
#               "hn_algolia"    Hacker News Algolia JSON (target = full URL)
#   target  — query text / TOPIC token / full URL, per kind.
#   lang/geo— only used by the gnews_* kinds to build hl/gl/ceid; ignored
#             (may be None) for absolute-URL kinds.
#
# Sources are all key-free and were curl-verified http=200 (2026-07-26):
#   Google News RSS search/topic, Hacker News Algolia, arXiv cs.AI RSS.
# ---------------------------------------------------------------------------
NEWS_FEEDS = (
    # ai-tech: Chinese AI headlines + arXiv AI papers + HN front page
    ("ai-tech", "gnews_search", "人工智能", "zh-CN", "CN"),
    ("ai-tech", "rss", "https://export.arxiv.org/rss/cs.AI", None, None),
    ("ai-tech", "hn_algolia",
     "https://hn.algolia.com/api/v1/search?tags=front_page", None, None),
    # hn: Hacker News community front page (points / comments carried as score)
    ("hn", "hn_algolia",
     "https://hn.algolia.com/api/v1/search?tags=front_page", None, None),
    # finance / investing: English business section + Chinese investing keyword
    ("finance", "gnews_topic", "BUSINESS", "en-US", "US"),
    ("finance", "gnews_search", "投资", "zh-CN", "CN"),
    # world: English world section
    ("world", "gnews_topic", "WORLD", "en-US", "US"),
    # china: Chinese "中国" keyword
    ("china", "gnews_search", "中国", "zh-CN", "CN"),
    # us-china relations: Chinese "中美关系" keyword
    ("us-china", "gnews_search", "中美关系", "zh-CN", "CN"),
)

# ---------------------------------------------------------------------------
# Source registry: canonical source names -> whether they feed L3 merge.
# memory_* sources stop at L2 (queried directly), per design.
# ---------------------------------------------------------------------------
SOURCES = (
    "raven",
    "claude_jsonl",
    "multica_issue",
    "multica_run",
    "multica_comment",
    "claude_job",
    "pr_cache",
    "ado_pr",
    "state_db",
    "hermes_tools",
    "hermes_messages",
    "claude_prompts",
    "codex_prompts",
    "kimi_prompts",
    "memory_claude",
    "memory_hermes_db",
    "memory_hermes_md",
    "github_repo",
    "github_pr",
    "news",
    "aidash_events",
    "local_git",
    "browser_history",
    "gecko",
)

MERGE_SOURCES = (
    "raven",
    "claude_jsonl",
    "multica_issue",
    "multica_run",
    "claude_job",
    "pr_cache",
    "ado_pr",
    "github_repo",
    "github_pr",
)


def raw_source_dir(source: str) -> Path:
    """Directory where a source's append-only raw shards live."""
    return RAW_DIR / source


def clean_path(source: str) -> Path:
    """Path to a source's normalized SQLite output."""
    return CLEAN_DIR / f"{source}.db"


# Agent-proposal inbox (§M3, goal ② "需要处理什么" — 待决策 bucket).
# An append-only JSONL file that autonomous agents (e.g. a future PM agent)
# write proposals into; the digest reads pending ones into the action inbox for
# the user to approve via AIDash's react model. Kept OUTSIDE the warehouse — it
# is human-facing state, not telemetry. One JSON object per line; see
# L5_apps/digest/proposals.py for the schema.
PROPOSALS_PATH = AIDATA_HOME / "L5_apps" / "digest" / "state" / "proposals.jsonl"


# ---------------------------------------------------------------------------
# Machine-local overrides (NOT in version control).
#
# This repo is public, so it carries no account, employer, or workspace
# identifiers — the constants above default to empty and every source that
# needs one degrades to a no-op (ADR-23). Real values live in config_local.py,
# which .gitignore excludes; copy config_local.example.py to get started.
#
# The star-import runs last on purpose: any name it defines rebinds the default
# above it, so a local file only has to state what it overrides.
# ---------------------------------------------------------------------------
try:
    from config_local import *  # noqa: F401,F403  (intentional override hook)
except ImportError:
    pass
