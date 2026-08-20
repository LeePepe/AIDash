# ADR-003: Sandbox the Fixed Install with Minimal Entitlements

## Status

Accepted

## Context

`scripts/dev/install-fixed-build.sh` builds an ad-hoc signed Release bundle
with `CODE_SIGNING_ALLOWED=NO` and no entitlements. The installed binary at
`/Applications/AIDash.app` is linker-signed with no TeamIdentifier, no App
Sandbox, and no CloudKit entitlements. This was intentional: the fixed install
is a dev-only local tool, and CloudKit unavailability is acceptable because the
headless XPC agent only needs local SwiftData.

`CloudKitContainer.storeURL()` pins the store to the app container path:

```
~/Library/Containers/<bundleID>/Data/Library/Application Support/AIDash/AIDash.store
```

This path was chosen specifically because it is the ONE location both sandboxed
and unsandboxed processes can reach (see CloudKitContainer.swift:225-228): a
sandboxed process resolves it as its own container (`NSHomeDirectory()`), and an
unsandboxed process can open it as a plain absolute path. One path, one store,
either build posture.

On macOS 26, this assumption broke. The container directory is now
**protected**: an unsandboxed process without the `com.apple.security.app-sandbox`
entitlement blocks indefinitely on `sqlite3BtreeOpen → robust_open2` when
trying to open a file inside `~/Library/Containers/<bundleID>/`. Process samples
consistently show the open stuck in `unixOpen → robust_open2`. Both the GUI
process and the XPC agent reproduce the same blocked open. The store is a
regular file on the local APFS data volume — the block is macOS container
access protection, not disk I/O or MainActor starvation.

An earlier attempt to work around this by changing `storeURL()` to use
`~/Library/Application Support/AIDash` for unsandboxed builds was rejected:
it creates a fresh empty store at a different path, making the existing
container store invisible — an explicit split-brain/data-orphaning violation
of Constitution §I (append-only events must not go missing) and the MY-1453
acceptance criteria.

## Decision

Change the fixed-install packaging posture from **unsandboxed / no entitlements**
to **sandboxed / minimal entitlements**. No code changes to `CloudKitContainer`,
`AppBootstrap`, `AgentContainerLoader`, `GUIContainerLoader`, or any other
runtime Swift file.

### New entitlements file

Create `Apps/AIDashApp/AIDashApp.macOS.fixed.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

### Entitlement set justification

| Entitlement | Included | Rationale |
|-------------|----------|-----------|
| `app-sandbox` | **Yes** | Required to access the container path on macOS 26. The sandbox confines the process to its container — which is exactly where the pinned store lives. |
| `network.client` | **No** | The fixed-install agent uses local-only SwiftData + Mach XPC. No demonstrated network requirement; omitting reduces attack surface. |
| `icloud-services` | **No** | CloudKit entitlements without a valid provisioning profile cause `NSPersistentCloudKitContainer` to `os_crash`/`brk 1`. Omitting them makes `hasCloudKitEntitlement()` return `false` → clean `.localOnly` fallback. This is the existing runtime behavior; the change is purely packaging. |
| `icloud-container-identifiers` | **No** | Same reason as above — no provisioning profile to back it. |
| `ubiquity-container-identifiers` | **No** | Same reason as above. |

### Install script changes

`install-fixed-build.sh` retains the current unsigned build flags
(`CODE_SIGNING_ALLOWED=NO`) and adds a deterministic post-build ad-hoc
codesign step. The signing order is **inside-out**: every nested executable
inside the app bundle must be individually signed before the outer app is
signed, so that each executable carries the sandbox entitlement in its own
code signature.

#### Signing order (inside-out, deterministic)

1. **Sign every nested executable first.** The app bundle contains at least
   the LaunchAgent/XPC helper (`AIDash.app/Contents/Library/LaunchAgents/`
   or `Contents/XPCServices/`). Each nested Mach-O must be ad-hoc signed
   with the same fixed entitlements before the outer bundle signature is
   applied:

   ```bash
   # Sign each nested executable with sandbox entitlements:
   find "$APP_SRC/Contents" \( -name "*.xpc" -o -type f -perm +111 \) \
     ! -path "$APP_SRC/Contents/MacOS/*" -print0 | while IFS= read -r -d '' nested; do
       codesign --force --sign - \
         --entitlements Apps/AIDashApp/AIDashApp.macOS.fixed.entitlements \
         "$nested"
   done
   ```

2. **Sign the outer app bundle last**, sealing all nested signatures:

   ```bash
   codesign --force --sign - \
     --entitlements Apps/AIDashApp/AIDashApp.macOS.fixed.entitlements \
     "$APP_SRC"
   ```

Signing only the outer app is **insufficient**: nested executables spawned
by launchd (e.g. the XPC agent registered via a LaunchAgent plist) run as
independent processes. macOS evaluates each process's own code signature for
sandbox enforcement. A nested executable that inherits an outer-only
signature but has no embedded entitlements of its own will run unsandboxed
and fail to access the protected container on macOS 26.

This approach is preferred over passing `CODE_SIGNING_ALLOWED=YES` +
`CODE_SIGN_ENTITLEMENTS` through xcodebuild, which may interact
unpredictably with the placeholder `AIDASH_DEVELOPMENT_TEAM = REPLACE_ME`
and the absence of a provisioning profile. Post-build codesign is
deterministic: the entitlements are embedded exactly as specified, ad-hoc
signed, with no dependency on team identity or provisioning state.

### Store-dependent self-check

The installer must verify both store-independent and store-dependent XPC
operation after signing and installing the bundle. Two probes are required,
run sequentially:

1. **Store-independent probe** (schema availability):

   ```bash
   aidash schema list --quiet
   ```

   This confirms the XPC agent started and the Mach service is reachable.
   It does not open the SwiftData store and therefore cannot detect
   container-access failures.

2. **Store-dependent probe** (container read under sandbox):

   ```bash
   aidash briefing get --date today --json
   ```

   This forces the XPC agent to open the SwiftData store inside the
   protected container path, execute a query, and return a result. If the
   sandbox entitlement is missing or incorrectly applied, this probe will
   block on `sqlite3BtreeOpen → robust_open2` (the exact failure mode
   documented in the Context section).

#### Cold-start timeout and failure conditions

Both probes must complete within a **30-second wall-clock timeout** per
probe (60 seconds total). The cold-start budget accounts for:
- launchd agent bootstrap (~2 s),
- SwiftData `ModelContainer` initialization (~3–5 s first launch),
- SPM package graph resolution (not applicable at runtime).

**Failure conditions** (any one triggers installer failure):
- Probe 1 (`schema list --quiet`) exits non-zero or exceeds 30 s.
- Probe 2 (`briefing get --date today --json`) exits non-zero, exceeds
  30 s, or returns malformed JSON (missing top-level `briefings` key).
- Probe 2 returns a valid empty result (no briefings for today) — this is
  a **PASS**: it proves the store was opened and queried successfully.

If either probe fails, the installer must print the probe command, its
exit code, and any stderr, then exit non-zero. The user should check that
the installed binary has the correct entitlements (`codesign -d --entitlements :-
/Applications/AIDash.app/Contents/MacOS/AIDash`).

## Analysis

### Fixed install remains local-only

The fixed install has always been local-only: no CloudKit entitlements → no
CloudKit sync. This decision does not change that. The headless XPC agent
(`AgentContainerLoader`) already forces `.localOnly` regardless of CloudKit
availability because `NSPersistentCloudKitContainer` SIGTRAPs in a headless
launchd-agent context.

### LaunchAgent sandbox compatibility

The XPC agent runs as a launchd-agent via `launchctl bootstrap gui/<uid>`.
The LaunchAgent installer (`LaunchdAgentInstaller.swift`) deliberately uses
plain `launchctl bootstrap` instead of `SMAppService` to avoid Lightweight
Code Requirement (LWCR) issues with debug builds. This remains unchanged.

Mach services brokered by launchd work inside the App Sandbox. The XPC
connection between CLI (`aidash`) and the sandboxed agent uses a Mach
service name registered in the LaunchAgent plist. launchd brokers the
connection regardless of sandbox posture — the sandbox does not restrict
incoming Mach service connections that launchd has registered for the job.

The agent's file access is confined to its container. This is compatible
because:
- SwiftData store: lives inside `~/Library/Containers/<bundleID>/Data/...`
  (the agent's own container).
- XPC communication: Mach services, no filesystem dependency.
- No CloudKit: agent uses `.localOnly`, no network required for sync.

### Two entitlements files

| Build | Entitlements file | Sandbox | CloudKit |
|-------|-------------------|---------|----------|
| Xcode dev / Release | `AIDashApp.macOS.entitlements` | Yes | Yes (provisioned) |
| Fixed install | `AIDashApp.macOS.fixed.entitlements` | Yes | No (no profile) |

The full entitlements file remains the default in `project.yml`. The fixed
entitlements file is referenced only in `install-fixed-build.sh` via the
post-build `codesign` step. No change to `project.yml`.

### Ad-hoc signing and Gatekeeper

An ad-hoc signed (`-`) sandboxed binary is a locally built artifact. Since
`install-fixed-build.sh` builds and installs on the same machine, macOS does
not apply quarantine to the output — the binary is never downloaded from the
internet. Standard Gatekeeper prompts should not apply to locally built
artifacts installed via `ditto` + `mv`.

If Gatekeeper friction is observed in practice, a future ADR can evaluate
Developer ID signing for the fixed install.

### Canonical store identity — unchanged

The store path remains:

```
~/Library/Containers/<bundleID>/Data/Library/Application Support/AIDash/AIDash.store
```

No migration, no path change, no code change in `CloudKitContainer.storeURL()`.
The sandboxed fixed-install process resolves this as its own container
(literally `NSHomeDirectory()` under sandbox). The Xcode dev build (also
sandboxed) resolves the same path. One store identity for all builds.

### Data contract — no fork, no migration

- **No new store path**: the fix changes packaging, not the store location.
- **No data move**: `legacyStoreURLs()` and `adoptLegacyStore` are unchanged.
  Legacy adoption runs on first access if needed, as designed.
- **No split-brain**: both sandboxed builds (Xcode and fixed) and the
  previously-unsandboxed fixed build all pin to the same container path.
  There is no second path to diverge into.
- **No in-memory fallback**: `ModelContainer` still opens the persistent
  SQLite store or fails with `.failed(reason:)`.

### Constitution alignment

| Principle | Status |
|-----------|--------|
| §I Append-only events | **Preserved** — same store, no data loss path |
| §II CLI writes / App reads | **Preserved** — CLI remains thin XPC client |
| App owns sole CloudKit identity | **Preserved** — fixed install has no CloudKit |
| Swift 6 strict concurrency | **Preserved** — no code changes |
| No `fatalError`/`try!`/`as!` | **Preserved** — no code changes |
| No unsafe concurrency escape | **Preserved** — no code changes |

## Alternatives considered

1. **Change `storeURL()` to use `~/Library/Application Support/AIDash` for
   unsandboxed builds.** Rejected: creates a second store path → split-brain.
   This was attempted and stopped by the project owner (MY-1453 re-scope).

2. **Use `NSHomeDirectory()` dynamically.** The pinned path already uses this
   indirectly: `realHomeDirectory()` resolves the true home, and the container
   path under it is the intersection. Switching to `NSHomeDirectory()` directly
   would make the path vary with sandbox posture (the opposite of what we need).

3. **Developer ID sign the fixed install.** Would eliminate Gatekeeper friction
   and could theoretically enable notarization. Requires managing a Developer
   ID certificate + provisioning workflow for a dev-only tool. Over-engineered
   for current needs; can be revisited if distribution scope widens.

4. **TCC / Full Disk Access prompt for unsandboxed binary.** macOS 26 container
   protection is not a TCC consent gate — it is a hard sandbox enforcement.
   Full Disk Access does not bypass container path protection for non-sandboxed
   processes attempting to access another process's container.

5. **Keep unsandboxed, move store outside containers.** Equivalent to
   alternative 1 — any path outside the container creates a new store identity.

## Consequences

- The fixed-install binary gains App Sandbox, confining it to its container.
  This is a security improvement: the dev tool no longer has unrestricted
  filesystem access.
- CloudKit remains unavailable in fixed installs (unchanged behavior).
- Gatekeeper should not apply to locally built artifacts (no quarantine on
  `ditto`/`mv` from a local build).
- Two entitlements files must be maintained: full (Xcode) and minimal (fixed).
  The risk of drift is low because the fixed file is intentionally minimal
  (1 key: `app-sandbox` only) and rarely changes.
- Future changes to the store path or sandbox posture require updating this
  ADR.
