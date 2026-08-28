---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "RepoInfra",
  "parent": "CONTEXT.md",
  "scope": [".claude/**", ".github/**", ".specify/**", "design/**", "docs/**", "scripts/**", "specs/**", ".gitignore", ".require-tests-ignore", ".swiftlint.yml", "AGENTS.md", "CLAUDE.md", "README.md", "tech-context.md"],
  "dependencies": [],
  "dependents": [],
  "red_lines": [
    "The recursive resolver is the single routing source for hooks and CI.",
    "Resolver-declared leaf gate failures emitted by context/run include layer, path, kind, detail, and red_lines.",
    "Existing mandatory lint, test, anti-rot, and CI build gates remain enforced.",
    "Repository automation never runs local host-based AIDashAppTests."
  ],
  "gates": [
    {"id": "repo-tests-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "scripts/ci/tests", "scripts/context/tests", "-q"]},
    {"id": "repo-tests-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "scripts/ci/tests", "scripts/context/tests", "-q"]},
    {"id": "hook-syntax", "kind": "lint", "mode": "both", "command": ["bash", "-n", "scripts/hooks/pre-commit", "scripts/hooks/pre-push"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "scripts/ci", "scripts/context"]}
  ]
}
---

# RepoInfra

Owns specifications, agent instructions, documentation, design references,
quality scripts, git hooks, and CI workflows. Product and data code remain in
their routed leaves.
