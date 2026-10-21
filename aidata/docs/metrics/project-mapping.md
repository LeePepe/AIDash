# Project mapping

The common `repo` key is resolved at L2 from a source working directory:

- `git rev-parse --show-toplevel`, followed by `git remote get-url origin`,
  yields the final `owner/name` path from the origin URL.
- A git repository without an origin uses `local:<top-level basename>`.
- A missing or non-git directory uses `(unresolved)`.
- Hermes uses `git_repo_root` first and `cwd` second. Claude turns use the
  latest same-session prompt at or before the turn, or the earliest prompt if
  none qualifies. Equal timestamps use `prompt_id` descending/ascending.
- Raven Codex/Multica rows have no project bridge and are `(unattributed)`.

`tokens/by-project` groups by CST day and repo and reports input, output,
cache-read, cache-write, cost, and input-plus-output share. Unattributed and
unresolved rows remain in the denominator; cache tokens do not.
