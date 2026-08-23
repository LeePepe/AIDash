---
{
  "schema": 1,
  "kind": "index",
  "routes": [
    {"patterns": ["Packages/**"], "context": "Packages/CONTEXT.md"},
    {"patterns": ["Apps/**"], "context": "Apps/CONTEXT.md"},
    {"patterns": ["CLI/**"], "context": "CLI/CONTEXT.md"},
    {"patterns": ["aidata/**"], "context": "aidata/CONTEXT.md"},
    {"patterns": ["Configs/**", "fastlane/**", "project.yml"], "context": "Configs/CONTEXT.md"},
    {"patterns": [".claude/**", ".github/**", ".specify/**", "design/**", "docs/**", "scripts/**", "specs/**", ".gitignore", ".require-tests-ignore", ".swiftlint.yml", "AGENTS.md", "CLAUDE.md", "README.md", "tech-context.md"], "context": "scripts/CONTEXT.md"}
  ],
  "exclusions": [
    {"patterns": ["CONTEXT.md"], "reason": "Root routing metadata; it is audited as context structure rather than owned product code."}
  ]
}
---

# AIDash context router

Resolve the file being changed with `scripts/context/resolve <path>`, then read
the returned context chain. Run `scripts/context/audit` after changing routing,
dependencies, manifests, hooks, or context documents.
