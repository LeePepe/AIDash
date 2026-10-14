"""Machine-local config overrides — COPY THIS FILE to config_local.py.

    cp config_local.example.py config_local.py

config.py imports `from config_local import *` as its LAST statement, so every
name defined here rebinds the default that config.py declared. Only state what
you actually override — anything omitted keeps config.py's default.

config_local.py is git-ignored on purpose: it holds account, employer, and
workspace identifiers that must never land in this public repo. Without it the
sources below simply collect nothing (ADR-23 degrade-not-crash), so the digest
still builds on a fresh machine.
"""

# ---------------------------------------------------------------------------
# Multica workspaces the digest collects from (ADR-5 / EXT-2).
# An allow-list of (workspace_uuid, friendly_name). The friendly name appears
# verbatim in the digest's per-workspace breakdown. Each workspace keeps its own
# watermark (ADR-19). Leave as () to collect from none.
# ---------------------------------------------------------------------------
MULTICA_WORKSPACES = (
    ("00000000-0000-0000-0000-000000000000", "WorkspaceA"),
    ("11111111-1111-1111-1111-111111111111", "my"),
)

# ---------------------------------------------------------------------------
# Azure DevOps PR source (EXT-4, ADR-6/22).
# ADO_CREATOR_ID is the ADO-*native* creator descriptor from a PR's
# `createdBy.id` — NOT the AAD object id from `az ad signed-in-user show` (on
# ADO Server those are different namespaces and the AAD id matches nothing).
# To find yours: open one of your PRs and read `createdBy.id`, e.g.
#     az repos pr list --repository <repo> --project <proj> --org <org> \
#        --creator <you@example.com> --top 1 --output json | jq '.[0].createdBy'
# All five must be set, or ado_pr collects nothing.
# ---------------------------------------------------------------------------
ADO_ORG = "https://example.visualstudio.com/DefaultCollection"
ADO_PROJECT = "MyProject"
ADO_REPO = "MyRepo"
ADO_CREATOR_EMAIL = "me@example.com"
ADO_CREATOR_ID = "00000000-0000-0000-0000-000000000000"

# ---------------------------------------------------------------------------
# GitHub repos whose PRs authored by you feed the "开了 N 个 PR" line.
# `gh pr list --author @me` runs per repo, reusing your existing gh auth.
# Empty (config.py's default) ⇒ the github_pr source collects nothing.
# ---------------------------------------------------------------------------
GITHUB_PR_REPOS = (
    "owner/repo",
)

# ---------------------------------------------------------------------------
# Optional path overrides — config.py's defaults are already HOME-relative and
# portable, so most people never need these. Uncomment only if your layout
# differs. Every one of these degrades to "skip this source" when absent
# (ADR-23), so a wrong path never crashes the digest.
# ---------------------------------------------------------------------------
# from pathlib import Path
# import os
# HOME = Path(os.path.expanduser("~"))
#
# # Team Workflow Audit bundle import root for the explicit manual source.
# # Leave blank to keep the source disabled; a non-empty directory allows the
# # operator to run `aidata/cli.py collect --source team_audit_snapshot`.
# TEAM_AUDIT_IMPORT_ROOT = ""
#
# # Roots walked for `.git` repos to aggregate your own commit activity.
# # Keep this narrow — walking all of ~ is slow. Author email is read live from
# # `git config --global user.email`, never configured here.
# LOCAL_GIT_SCAN_ROOTS = (HOME / "Development",)
#
# # Curated watchlist folder for the GitHub tool-radar source (github_repo):
# # one Markdown note per tool, each carrying a github.com/owner/repo URL.
# COLLECTED_TOOLS_DIR = HOME / "Development" / "Personal" / "collected-tools"
#
# # multica CLI binary (falls back to a PATH lookup if this exact path is absent).
# MULTICA_BIN = "/opt/homebrew/bin/multica"
