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
    "Gate failures emit layer, path, kind, detail, and red_lines.",
    "Existing mandatory lint, test, anti-rot, and CI build gates remain enforced.",
    "Repository automation never runs local host-based AIDashAppTests."
  ],
  "gates": []
}
---

# RepoInfra

Owns specifications, agent instructions, documentation, design references,
quality scripts, git hooks, and CI workflows. Product and data code remain in
their routed leaves.
