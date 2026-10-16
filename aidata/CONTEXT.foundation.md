---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataFoundation",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": ["CONTEXT.foundation.md", "README.md", "tech-context.md", "pytest.ini", "requirements.lock", "cli.py", "cleanio.py", "config.py", "config_local.example.py", "rawio.py", "redaction.py", "sqlite_ro.py", "state.py", "timeutil.py", "docs/**"],
  "test_paths": ["tests/__init__.py", "tests/test_config_m3.py", "tests/test_config_multica.py", "tests/test_product_blob_cli.py", "tests/test_team_audit_manual_source.py", "tests/test_timeutil.py"],
  "dependencies": [],
  "dependents": ["AidataL1L2", "AidataL3", "AidataL4", "AidataL5", "AidataOps"],
  "red_lines": [
    "Tracked configuration contains neutral empty defaults; identities stay in ignored config_local.py.",
    "PRODUCT_BLOB_CONTAINER_URL plus one PRODUCT_BLOB_PREFIX are the only noncredential product_blob selectors; tracked defaults stay empty, the configured prefix is the Owner-allow-listed VoxPocket value, real values stay local, and no credential or auth-mode field is tracked.",
    "SCHEDULED_SOURCES preserves the current ordered unique runner set without activating unimplemented sources.",
    "requirements.lock contains the complete Python 3.13 runtime closure with one exact portable package==version line per package.",
    "Missing sources and configuration degrade to a no-op rather than crashing.",
    "Raw and clean I/O preserves redaction and append-only guarantees."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]},
    {"id": "degrade-not-crash", "kind": "test", "mode": "ci", "command": ["python3", "-c", "import pathlib,sys; assert not pathlib.Path('aidata/config_local.py').exists(); sys.path.insert(0, 'aidata'); import config; from adapters import ado_pr, github_pr; assert config.ADO_ORG == ''; assert config.MULTICA_WORKSPACES == (); assert config.GITHUB_PR_REPOS == (); assert ado_pr.collect() == 0; assert github_pr.collect() == 0"]}
  ],
  "reference": "aidata/tech-context.md"
}
---

# AidataFoundation

Owns shared configuration, redaction, state, safe I/O, time, and CLI utilities
used across the Python pipeline. It contains no source-specific business logic.

The local `pytest-local` gate uses the existing `/usr/bin/python3` environment
for configuration tests; it does not install or validate `requirements.lock`.
Python 3.13 lock installation is the future T002 CI target, not current CI
behavior; current local configuration tests use `/usr/bin/python3`, do not
install the lock, and do not import the Azure dependency closure. Here, portable
means platform-neutral exact `package==version` lines, not Python 3.9 support.
