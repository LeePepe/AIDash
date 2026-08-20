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
codesign step that embeds the fixed entitlements into the app bundle.

#### Current bundle layout

```
AIDash.app/
  Contents/
    MacOS/AIDash          ← the one Mach-O; LaunchAgent Program points here
    Info.plist
    Resources/
    _CodeSignature/
```

#### Signing order (inside-out, three-phase, deterministic)

> **Codebase fact (as of this ADR):** The repo ships a single-executable
> app bundle with no nested XPC service, helper, or embedded framework.
> The LaunchAgent plist sets `Program` to the outer app's main executable
> (`/Applications/AIDash.app/Contents/MacOS/AIDash`), which handles both
> GUI and headless XPC-agent modes. The separately installed CLI
> (`~/.local/bin/aidash`) is outside the app bundle and does not access
> the SwiftData store. Phases 1 and 2 below are therefore **no-ops today**
> and exist as **fail-closed future-proofing**: if a future change adds
> nested code, the signing contract is already correct and the
> verification gate will catch any signing omission.

The signing contract has three phases executed strictly in order. Each
phase uses a **separate enumeration pass** — never a single combined
traversal that could sign a bundle directory before its inner contents.
No later phase may modify the contents of a bundle signed in an earlier
phase.

```bash
ENTITLEMENTS="Apps/AIDashApp/AIDashApp.macOS.fixed.entitlements"
```

**Phase 1 — Leaf executables and libraries.** Enumerate regular files
inside `Contents/` that are either executable or are dynamic libraries,
excluding only the exact outer main binary
(`$APP_SRC/Contents/MacOS/AIDash`) — not all of `Contents/MacOS/*`,
because a future build may place additional helper executables there that
must be signed in this phase. Before signing each file, verify it is a
Mach-O binary; skip non-Mach-O executables (e.g. shell scripts with `+x`).

The script **must run under `set -uo pipefail`**. Because `while read`
in a pipeline runs in a subshell whose exit status is masked by
`pipefail` only reporting the last non-zero component, use a
process-substitution form that propagates `codesign` failures to the
calling shell:

```bash
# Phase 1: sign leaf Mach-O executables/dylibs (regular files only)
signed_count=0
while IFS= read -r -d '' leaf; do
    # Capture file type without a pipe — avoids pipefail/SIGPIPE
    filetype=$(/usr/bin/file -b "$leaf") || {
        echo "FATAL: /usr/bin/file failed on $leaf"; exit 1; }
    case "$filetype" in *Mach-O*) ;; *) continue ;; esac
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$leaf" \
      || { echo "FATAL: codesign failed on $leaf"; exit 1; }
    signed_count=$((signed_count + 1))
done < <(find "$APP_SRC/Contents" -type f \( -perm +111 -o -name "*.dylib" \) \
  ! -path "$APP_SRC/Contents/MacOS/AIDash" \
  -print0)
```

**Phase 2 — Nested code bundles (deepest-first).** In a **separate**
enumeration pass, sign `.xpc`, `.appex`, and nested `.app` bundle
directories inside `Contents/`. The traversal uses `find -depth` to
guarantee depth-first (post-order) processing: inner bundles are always
visited before enclosing bundles, regardless of directory name sort order.
`-depth` is the depth-order guarantee — never substitute `sort -rz`
(reverse lexicographic, which does not guarantee depth ordering).

```bash
# Phase 2: sign nested code bundles depth-first (post-order traversal)
while IFS= read -r -d '' bundle; do
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$bundle" \
      || { echo "FATAL: codesign failed on $bundle"; exit 1; }
    signed_count=$((signed_count + 1))
done < <(find "$APP_SRC/Contents" -depth -type d \
  \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) -print0)
```

**Phase 3 — Outer app bundle.** Sign the top-level `.app` last, sealing
all nested signatures from Phases 1 and 2.

```bash
# Phase 3: sign the outer app bundle last
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_SRC"
```

#### Post-sign verification gate (fail-closed)

After all three phases, the installer **must** verify the result. The
verification confirms deep signature integrity and that **every** signed
Mach-O and nested bundle target carries the `app-sandbox` entitlement —
not just the main executable.

```bash
# 1. Deep signature integrity (covers all nested signatures)
codesign --verify --deep --strict "$APP_SRC" \
  || { echo "FATAL: codesign --verify --deep --strict failed"; exit 1; }

# Helper: capture-first entitlement check (no grep -q pipeline)
check_sandbox_entitlement() {
    local target=$1
    local ent_out
    ent_out=$(codesign -d --entitlements :- "$target" 2>&1) || {
        echo "FATAL: codesign -d failed on $target"; exit 1; }
    case "$ent_out" in
        *com.apple.security.app-sandbox*) ;;
        *) echo "FATAL: app-sandbox entitlement missing on $target"; exit 1 ;;
    esac
}

# 2. Verify app-sandbox entitlement on the main executable
check_sandbox_entitlement "$APP_SRC/Contents/MacOS/AIDash"

# 3. Verify app-sandbox entitlement on every target signed in Phases 1/2
if [ "$signed_count" -gt 0 ]; then
    # Re-enumerate leaf targets and check each one
    while IFS= read -r -d '' target; do
        filetype=$(/usr/bin/file -b "$target") || {
            echo "FATAL: /usr/bin/file failed on $target"; exit 1; }
        case "$filetype" in *Mach-O*) ;; *) continue ;; esac
        check_sandbox_entitlement "$target"
    done < <(find "$APP_SRC/Contents" -type f \( -perm +111 -o -name "*.dylib" \) \
      ! -path "$APP_SRC/Contents/MacOS/AIDash" -print0)

    # Re-enumerate nested bundles and check each one
    while IFS= read -r -d '' target; do
        check_sandbox_entitlement "$target"
    done < <(find "$APP_SRC/Contents" -depth -type d \
      \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) -print0)
fi
```

If any verification step fails, the installer must exit non-zero without
proceeding to install. This is fail-closed: a target missing `app-sandbox`
or a broken nested signature is never silently installed.

#### Design rationale

**Why inside-out?** macOS evaluates each process's own code signature
for sandbox enforcement. The LaunchAgent `Program` today points to the
outer app executable, so signing the outer `.app` alone is sufficient
for the current single-executable layout. However, if a future change
adds a nested XPC service or helper that launchd spawns as a separate
process, that nested executable must carry its own embedded entitlements
— an outer-only signature would leave it unsandboxed and unable to
access the protected container on macOS 26.

**Why separate enumeration passes?** A single combined `find` that
matches both `-type f` executables and `-type d` bundle directories in
one traversal can process them in pre-order (parent before children).
This signs the `.xpc` bundle directory before its inner executable,
then re-signs that executable — mutating the already-sealed bundle and
invalidating its signature. Separate passes guarantee Phase 1 (leaves)
completes before Phase 2 (enclosing bundles) begins.

This approach is preferred over passing `CODE_SIGNING_ALLOWED=YES` +
`CODE_SIGN_ENTITLEMENTS` through xcodebuild, which may interact
unpredictably with the placeholder `AIDASH_DEVELOPMENT_TEAM = REPLACE_ME`
and the absence of a provisioning profile. Post-build codesign is
deterministic: the entitlements are embedded exactly as specified, ad-hoc
signed, with no dependency on team identity or provisioning state.

### Store-dependent self-check

The installer must verify both store-independent and store-dependent XPC
operation after signing and installing the bundle. Two probes are required,
run sequentially.

#### 30-second timeout runner (stock macOS `/usr/bin/perl`)

Stock macOS does not ship GNU `timeout`. The shell-based watcher/sleep
approach has fundamental flaws: the watcher sleeps the full timeout even
on immediate success, and after `wait` reaps the child PID, the OS can
reassign that PID to an unrelated process which the watcher then kills.

The runner instead uses a single `/usr/bin/perl` supervisor process
(guaranteed on stock macOS 26). The parent `fork`s the child, sets
`alarm`, and calls `waitpid`. Because the parent **owns the unreaped
child PID throughout**, PID reuse is impossible. Immediate success
returns immediately (no sleeping watcher to cancel). No watcher/sleep
subprocess is created at all.

**Protocol:**

1. Parent opens stdout/stderr files, `fork`s, and calls `alarm($limit)`.
2. Child `exec`s the command with stdout/stderr redirected to the files.
3. Parent blocks on `waitpid($pid, 0)`.
4. If `SIGALRM` fires first, the handler calls `waitpid($pid, WNOHANG)`.
   If the child has already exited (was reaped), the handler preserves
   that exit status and clears the timeout flag — **no false timeout**.
   Otherwise the child is still alive: mark timeout, `kill(KILL, $pid)`,
   and `waitpid` to reap.
5. After `waitpid` returns in the main loop, the parent exits with 124
   if the timeout flag won, `WEXITSTATUS` for normal exit, or
   `128 + WTERMSIG` for signal death.
6. All `fork`/`open`/`exec`/`waitpid` failures are fatal (`die`).

```bash
# run_with_timeout SECONDS STDOUT_FILE STDERR_FILE CMD [ARGS...]
# Writes child stdout/stderr to the named files.
# Returns: child exit status, or 124 on timeout.
run_with_timeout() {
    /usr/bin/perl -e '
use strict;
use warnings;
use POSIX qw(WNOHANG WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG);

my $limit    = shift @ARGV or die "usage: run_with_timeout LIMIT OUT ERR CMD...\n";
my $out_file = shift @ARGV or die "missing stdout file\n";
my $err_file = shift @ARGV or die "missing stderr file\n";
@ARGV or die "missing command\n";

open(my $out_fh, ">", $out_file) or die "open $out_file: $!\n";
open(my $err_fh, ">", $err_file) or die "open $err_file: $!\n";

my $timed_out   = 0;
my $reaped_rc;          # set if SIGALRM handler reaps the child early

my $pid = fork();
defined $pid or die "fork: $!\n";

if ($pid == 0) {
    # Child: redirect stdout/stderr, exec command
    open(STDOUT, ">&", $out_fh) or die "dup stdout: $!\n";
    open(STDERR, ">&", $err_fh) or die "dup stderr: $!\n";
    exec @ARGV or die "exec $ARGV[0]: $!\n";
}

# Parent: close file handles (child owns them now)
close $out_fh;
close $err_fh;

$SIG{ALRM} = sub {
    # Try non-blocking reap: if child already exited, preserve its status
    my $w = waitpid($pid, WNOHANG);
    if ($w == $pid) {
        # Child already exited — NOT a timeout
        if    (WIFEXITED($?))   { $reaped_rc = WEXITSTATUS($?); }
        elsif (WIFSIGNALED($?)) { $reaped_rc = 128 + WTERMSIG($?); }
        else                    { $reaped_rc = 255; }
        return;  # main waitpid will see -1 / already reaped
    }
    # Child still alive — real timeout
    $timed_out = 1;
    kill("KILL", $pid) or die "kill $pid: $!\n";
    waitpid($pid, 0);  # reap the killed child
};

alarm($limit);
my $w = waitpid($pid, 0);
alarm(0);  # cancel alarm if child exited before timeout

my $rc;
if (defined $reaped_rc) {
    # SIGALRM handler already reaped — use its captured status
    $rc = $reaped_rc;
} elsif ($timed_out) {
    $rc = 124;
} elsif ($w == $pid) {
    if    (WIFEXITED($?))   { $rc = WEXITSTATUS($?); }
    elsif (WIFSIGNALED($?)) { $rc = 128 + WTERMSIG($?); }
    else                    { $rc = 255; }
} else {
    die "waitpid returned unexpected $w: $!\n";
}

exit $rc;
' "$@"
}
```

#### Probe helpers

Every probe failure must print the literal command, numeric exit status,
and captured stderr — the three-tuple promised by this ADR:

```bash
# probe_fail PROBE_NAME COMMAND_STRING EXIT_CODE STDERR_FILE
probe_fail() {
    local name=$1 cmd=$2 rc=$3 err_file=$4
    echo "FATAL: $name failed"
    echo "  command: $cmd"
    echo "  exit:    $rc"
    echo "  stderr:  $(cat "$err_file" 2>/dev/null)"
    exit 1
}
```

#### Probe 1 — store-independent (schema availability)

```bash
p1_cmd="aidash schema list --quiet"
p1_out=$(mktemp) p1_err=$(mktemp)
run_with_timeout 30 "$p1_out" "$p1_err" aidash schema list --quiet
p1_rc=$?
if [ "$p1_rc" -eq 124 ]; then
    probe_fail "probe 1 (timeout)" "$p1_cmd" "$p1_rc" "$p1_err"
fi
if [ "$p1_rc" -ne 0 ]; then
    probe_fail "probe 1" "$p1_cmd" "$p1_rc" "$p1_err"
fi
rm -f "$p1_out" "$p1_err"
```

This confirms the XPC agent started and the Mach service is reachable.
It does not open the SwiftData store and therefore cannot detect
container-access failures.

#### Probe 2 — store-dependent (container read under sandbox)

```bash
p2_cmd="aidash briefing get --date today --json"
p2_out=$(mktemp) p2_err=$(mktemp)
run_with_timeout 30 "$p2_out" "$p2_err" aidash briefing get --date today --json
p2_rc=$?
if [ "$p2_rc" -eq 124 ]; then
    probe_fail "probe 2 (timeout)" "$p2_cmd" "$p2_rc" "$p2_err"
fi
```

This forces the XPC agent to open the SwiftData store inside the
protected container path, execute a query, and return a result. If the
sandbox entitlement is missing or incorrectly applied, this probe will
block on `sqlite3BtreeOpen → robust_open2` (the exact failure mode
documented in the Context section) and hit the 30 s timeout.

#### Probe 2 exit-code validation (aligned with CLI contract)

The `aidash` CLI uses structured JSON envelopes. The installer must
validate both the exit code and the envelope shape. Validation uses
`/usr/bin/plutil` (guaranteed on stock macOS) to convert JSON to XML
plist, then pattern-matches required keys — no dependency on `python3`
or any package manager binary that could prompt, hang, or be absent.

| Exit code | Meaning | Installer action |
|-----------|---------|------------------|
| 0 | Success — `{"ok":true,"data":...,"requestId":"..."}` | **PASS** if envelope has `ok`=`true`, `data` present, `requestId` present. |
| 3 | Domain error — `{"ok":false,"error":{"code":"briefing.not_found",...,"requestId":"..."}}`; root `requestId` absent | **PASS** — proves store was opened and queried; no briefing exists for today. |
| Any other | Infrastructure/XPC/timeout failure | **FAIL** |

```bash
# validate_json_key FILE KEY EXPECTED_VALUE
# Uses /usr/bin/plutil to check a top-level key in a JSON file.
# Returns 0 if key exists and value matches (or EXPECTED_VALUE is empty
# for existence-only check), 1 otherwise.
validate_json_key() {
    local file=$1 key=$2 expected=$3
    local val
    val=$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null) \
      || return 1
    if [ -n "$expected" ] && [ "$val" != "$expected" ]; then
        return 1
    fi
    return 0
}

case "$p2_rc" in
    0)
        # Must be a valid success envelope: ok=true, data present, requestId present
        if ! validate_json_key "$p2_out" "ok" "true"; then
            probe_fail "probe 2 (ok!=true)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_out" "data" ""; then
            probe_fail "probe 2 (missing data)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_out" "requestId" ""; then
            probe_fail "probe 2 (missing requestId)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        ;;
    3)
        # Must be a valid briefing.not_found error envelope on STDERR:
        # ok=false, error.code=briefing.not_found, error.requestId present,
        # root requestId ABSENT (error envelopes carry requestId inside error)
        if ! validate_json_key "$p2_err" "ok" "false"; then
            probe_fail "probe 2 exit 3 (ok!=false)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_err" "error.code" "briefing.not_found"; then
            probe_fail "probe 2 exit 3 (error.code mismatch)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_err" "error.requestId" ""; then
            probe_fail "probe 2 exit 3 (missing error.requestId)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if validate_json_key "$p2_err" "requestId" ""; then
            probe_fail "probe 2 exit 3 (unexpected root requestId)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        ;;
    *)
        probe_fail "probe 2" "$p2_cmd" "$p2_rc" "$p2_err"
        ;;
esac
rm -f "$p2_out" "$p2_err"
```

#### Cold-start timeout budget

Both probes must complete within **30 seconds** each (60 seconds total).
The cold-start budget accounts for:
- launchd agent bootstrap (~2 s),
- SwiftData `ModelContainer` initialization (~3–5 s first launch).

If either probe fails, the installer prints the literal command, numeric
exit code, and captured stderr, then exits non-zero. The user should check
that the installed binary has the correct entitlements
(`codesign -d --entitlements :- /Applications/AIDash.app/Contents/MacOS/AIDash`).

## Analysis

### Fixed install remains local-only

The fixed install has always been local-only: no CloudKit entitlements → no
CloudKit sync. This decision does not change that. The headless XPC agent
(`AgentContainerLoader`) already forces `.localOnly` regardless of CloudKit
availability because `NSPersistentCloudKitContainer` SIGTRAPs in a headless
launchd-agent context.

### LaunchAgent sandbox compatibility

The LaunchAgent plist sets `Program` to the outer app's main executable:
`/Applications/AIDash.app/Contents/MacOS/AIDash`. There is no separate
nested XPC helper binary — the main executable handles both GUI and
headless XPC-agent modes. `LaunchdAgentInstaller.swift` deliberately
uses plain `launchctl bootstrap` instead of `SMAppService` to avoid
Lightweight Code Requirement (LWCR) issues with debug builds. This
remains unchanged.

Mach services brokered by launchd work inside the App Sandbox. The XPC
connection between the CLI (`aidash`, a separately installed standalone
binary at `~/.local/bin/aidash` that does not access the store) and the
sandboxed agent uses a Mach service name registered in the LaunchAgent
plist. launchd brokers the connection regardless of sandbox posture —
the sandbox does not restrict incoming Mach service connections that
launchd has registered for the job.

The agent process's file access is confined to its container. This is
compatible because:
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

**MY-1453 implementation prohibition:** The follow-up implementation issue
(MY-1453) **must not** change `CloudKitContainer.storeURL()`,
`legacyStoreURLs()`, or any store-path resolution logic. It must not
enumerate, copy, move, delete, or repair the real SwiftData store file or
its WAL/SHM companions. The scope of MY-1453 is strictly packaging and
signing — if a store-path change appears necessary, stop and file a new ADR.
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

### Rollback / supersession condition

If either tight probe (`aidash schema list --quiet` or
`aidash briefing get --date today --json`) fails **because** the sandboxed
ad-hoc binary cannot register or check in to its Mach service, or cannot
open the protected container store, this ADR must be **superseded** — not
patched around. Specifically:

- Do **not** fall back to a second store path, an unsandboxed posture, or a
  `~/Library/Application Support/` alternative. Any such fallback creates
  split-brain and violates Constitution §I.
- Do **not** add TCC / Full Disk Access workarounds for the container
  protection — macOS 26 container access is a hard sandbox enforcement, not
  a consent gate.
- Instead, **stop** the MY-1453 implementation, file a new ADR that
  supersedes ADR-003, and re-evaluate the signing/packaging approach from
  first principles before resuming.
