# CLAUDE.md

Read `AGENTS.md` first — it is the authoritative agent contract for this
repo, and `.specify/memory/constitution.md` governs everything in it.

This file exists to put the one rule that has caused real damage here in
front of you before you touch anything.

## Do not run tests proactively. The git hooks run them.

`scripts/hooks/pre-commit` and `pre-push` already run the correct set — SPM
package tests, then the four-target build gate — before anything leaves the
machine. Running suites by hand on top of that produces no extra signal, and
on this repo it has produced real harm twice.

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

**If you must verify an app-layer change** beyond the build gate, use the
hostless target — runs as `xctest`, launches no app, cannot reach the real
home:

```bash
xcodebuild -scheme AIDashAppLogicTests -destination 'platform=macOS' test
```

Host-based targets belong to CI, or to a run the user explicitly asks for.

The rule is about WHO runs tests, not WHICH tests are safe. "Only run the
safe ones" decays the moment you want to check one more thing; "let the
hooks do it" does not.

## Verification, ranked

1. Let the hooks run. They are the gate that actually matters.
2. Build gates (`xcodebuild ... build`) — cheap, no app launch, no prompts.
3. `swift test --package-path Packages/<X>` for package-local logic.
4. `AIDashAppLogicTests` for app-layer logic, when 1–3 cannot answer it.
