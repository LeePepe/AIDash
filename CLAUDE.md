# CLAUDE.md

Read `AGENTS.md` first — it is the authoritative agent contract for this
repo, and `.specify/memory/constitution.md` governs everything in it.

This file exists to put the one rule that has caused real damage here in
front of you before you touch anything.

## Do not run tests proactively. The git hooks run them.

`scripts/hooks/pre-commit` and `pre-push` resolve changed files through
`CONTEXT.md` and run their local leaf gates. Required App/CLI builds run in CI.
Running suites by hand on top of those gates produces no extra signal, and on
this repo it has produced real harm twice.

**Forbidden locally:**

```bash
xcodebuild -scheme AIDashApp ... test
```

`AIDashAppTests` pins `TEST_HOST` to the real `AIDash.app`, so the test
bundle runs **as the production app**: same bundle id, same real home, and a
freshly re-signed binary each build. Therefore, every run:

1. makes macOS re-prompt for TCC access (Contacts / iCloud — the app
   container symlinks to them), and
2. lets any code resolving the real home touch the user's **live data**. A
   test here once moved the user's SwiftData store into a temp directory and
   deleted it on teardown.

The resolver-selected hook may verify app-layer logic with the hostless
`AIDashAppLogicTests` product. It runs as `xctest`, launches no app, and cannot
reach the real home; humans and agents inspect its receipt rather than invoking
the product directly.

Host-based targets belong to CI, or to a run the user explicitly asks for.

The rule is about WHO runs tests, not WHICH tests are safe. "Only run the
safe ones" decays the moment you want to check one more thing; "let the
hooks do it" does not.

## Verification, ranked

1. Resolver-driven hook receipts for every changed owning leaf.
2. Permitted build, static-analysis, and contract checks.
3. Required CI receipts for heavy app/workspace builds and repository-wide
   suites.
