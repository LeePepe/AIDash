# Research Log: Core Briefing & CLI

> Phase 0 of `/speckit-plan`. Documents the architectural decisions that
> shaped `plan.md`, including alternatives considered and reasons for
> rejection. Each `R-N` is referenced from `plan.md`.

---

## R-1: CloudKit API choice

**Decision**: macOS app uses `NSPersistentCloudKitContainer` (SwiftData with
CloudKit auto-sync). The `aidash` CLI is a thin XPC client that calls
into the app; the CLI does **not** talk to CloudKit directly.

**Alternatives considered**:

- **A. Both processes hit CloudKit directly**, sharing a `Codable` schema
  in `AIDashCore` and dual-mapping to (a) SwiftData `@Model` in the app
  and (b) raw `CKRecord` in the CLI. Rejected because:
  - Two processes both running CloudKit subscriptions on the same
    `Container` is unsupported and produces non-deterministic sync.
  - CLI cold start to CloudKit ready ≈ 1–2s (private CKContainer
    initialization + iCloud account verification). Multiplied across 50
    CLI invocations per briefing = 50–100s of overhead per morning's
    briefing publish. Spec SC-001 requires ≤ 5s end-to-end for a full
    briefing publish.
  - Schema drift between SwiftData `@Model` and CKRecord field encoding
    is a constant maintenance tax.
- **B. Manual `CKDatabase` in both processes** (no SwiftData). Rejected
  because the app needs `@Query` reactivity in SwiftUI; implementing that
  on top of bare CloudKit means writing a 200+ line sync engine plus
  observer plumbing. SwiftData provides this for free.
- **C. The chosen design — app as the sole CloudKit owner, CLI talks XPC.**
  This collapses both problems: schema lives in one place (SwiftData
  `@Model` + Codable payload structs in `AIDashCore`), CloudKit identity
  lives in one process, CLI is mechanically simple.

**Consequence**: The app must be running for the CLI to function. This is
mitigated by:
- Auto-installing a LaunchAgent on first run (R-3).
- CLI auto-launches the app if it can't reach XPC, then polls for 5s (R-4).

---

## R-2: XPC protocol design

**Decision**: Single Obj-C protocol method
`execute(requestData: Data, reply: @escaping (Data) -> Void)`. All commands
flow as a JSON-RPC-style envelope serialized to `Data`. Schema lives in
`AIDashCore/XPC/`.

**Alternatives considered**:

- **Per-method `@objc protocol`**: one method per CLI subcommand
  (`putBriefing`, `putCard`, `pullEvents`, ...). Rejected because:
  - `@objc` protocols only carry Obj-C-compatible types (`NSString`,
    `NSDate`, `NSData`). Swift `struct` parameters must be erased to
    `Data` anyway — the per-method shape buys no real type safety.
  - Adding a new CardType would require a protocol change → app + CLI
    must rev together; a deployed-but-stale CLI can no longer talk to
    an upgraded app.
- **Mixed (high-traffic methods are typed, rest are generic)**: rejected
  for cognitive load — every new command provokes a "which bucket does
  this go in" decision.
- **The chosen single-method JSON-RPC**: schema-version-friendly, type
  safety recovered at the `XPCRequest`/`XPCResponse` Codable layer in
  `AIDashCore`. Both processes share the same Codable struct so the
  type check still happens, just one layer deeper.

**Envelope**:

```swift
public struct XPCRequest: Codable {
    public let command: String        // e.g. "card.put"
    public let params: Data           // type-specific payload, decoded per command
    public let requestId: String      // for logging / tracing
    public let cliVersion: String     // for forward-compat negotiation
}

public struct XPCResponse: Codable {
    public let ok: Bool
    public let data: Data?            // type-specific, nil on error
    public let error: XPCError?
}

public struct XPCError: Codable {
    public let code: String           // dotted: "schema.unknown_card_type"
    public let message: String
    public let field: String?         // for schema errors
    public let got: String?
    public let allowed: [String]?
}
```

**Validation discipline**: The CLI validates schema locally first using
the same `SchemaValidator` (`AIDashCore/Validation/`) that the app uses.
If the local check fails, the CLI returns to the agent immediately with
exit code 1; XPC is never invoked. If the local check passes, the app
re-validates server-side as defense-in-depth (covers CLI version drift).

---

## R-3: App lifecycle (LaunchAgent + menubar)

**Decision**:
- macOS app `Info.plist` sets `LSUIElement = true` (background app, no
  Dock icon, no cmd-Tab presence).
- Menubar item is the primary surface; clicking it opens the briefing
  window via a `WindowGroup` scene. Closing the window hides it; the
  process keeps running.
- The app self-installs a LaunchAgent on first run using
  `ServiceManagement.SMAppService.agent(plistName:)` (`SMAppService` is
  Apple's modern replacement for hand-rolled `launchctl bootstrap`).
- The launchd plist uses:
  ```xml
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
      <key>SuccessfulExit</key><false/>
      <key>Crashed</key><true/>
  </dict>
  <key>ThrottleInterval</key><integer>10</integer>
  ```

**Alternatives considered**:

- **LaunchDaemon (system-wide)**: rejected — runs as root, cannot access
  the user's iCloud Private DB.
- **Normal app + dock icon**: rejected — user wants "open occasionally,
  invisible otherwise" experience. Dock icon implies "this is a thing I
  juggle in cmd-Tab", which it is not.
- **App that quits on window close (no menubar)**: rejected — the CLI
  would have to launch the app on every single invocation, paying cold
  start each time (1–2s).
- **`KeepAlive: true` (bare boolean)**: rejected — user `cmd+Q` is
  treated as crash; user can never genuinely quit. The dict form with
  `SuccessfulExit=false` lets a clean quit stay quit.
- **`launchctl bootstrap` from a Makefile target**: rejected as
  user-facing friction. `SMAppService` is the modern, sandbox-friendly
  way (Apple's recommended API since macOS 13).

---

## R-4: CLI fallback when app not running

**Decision**: When the CLI fails to connect XPC, it tries
`NSWorkspace.shared.openApplication(at: …)` to launch the app, then polls
the XPC connection every 500ms for up to 10 attempts (5s total). Beyond
5s the CLI exits with code 2 and a structured error.

**Exit codes**:

| Code | Meaning | Agent's retry hint |
|---|---|---|
| 0 | Success | continue |
| 1 | Local validation failed (CLI rejected the input) | **do not retry**; fix input |
| 2 | XPC transport failed (app couldn't be launched / didn't register in 5s) | may retry with backoff |
| 3 | App-side business error (CloudKit quota, schema drift, conflict) | inspect `error.code` to decide |

**Why 4 codes**: agents only need three retry-strategies (fix-input,
backoff-retry, code-specific). A more granular set buys nothing —
specific reasons live in `error.code` already.

**Why 5s hardcoded**: spec SC-001 caps a full briefing publish at 5s
end-to-end. Allowing per-CLI timeout overrides would let an agent
silently degrade that contract. If real-world cold-start exceeds 5s, the
fix is to optimize app launch, not to lengthen the timeout.

**Alternatives considered**:

- **CLI also installs the LaunchAgent**: rejected — separation of concerns.
  The app owns its install. CLI's job is to call the app.
- **CLI falls back to direct CloudKit write when app missing**: rejected
  outright — defeats the whole point of R-1's app-as-sole-author design
  and reintroduces schema drift.

---

## R-5: Card payload polymorphism in SwiftData

**Decision**: SwiftData `@Model class CardModel` stores
`payloadJSON: Data`. Per-type Codable structs (`MetricPayload`,
`InsightPayload`, …) live in `AIDashCore/Models/Payloads/`. The
`CardType` enum has a `decodePayload(from:)` method that dispatches to
the right `JSONDecoder().decode(...)` call.

**Why SwiftData can't store the obvious shape directly**: A Swift `enum`
with associated values (e.g. `enum CardPayload { case metric(MetricPayload);
case insight(InsightPayload); ... }`) is not persistable by SwiftData. The
two available workarounds — one `@Model` class per type with cascading
relationships, or one giant `@Model` with every payload's fields as
optionals — both leak the type partition into the storage schema.

**Why `Data` works**:
- Codable round-trips through `JSONEncoder` / `JSONDecoder` are stable.
- CloudKit happily syncs `Data` fields up to the per-record size limit
  (1 MB; our payloads are < 50 KB worst case).
- Schema evolution is local to the Codable struct (add a property, give
  it a default; JSONDecoder ignores unknown keys = forward-compat per
  spec FR-031).
- CLI and App both `import AIDashCore` and share the same `XxxPayload`
  struct definitions — there is one schema source of truth.

**The "we lost type safety in storage" worry**: addressed by:
- The `CardType` enum is the gatekeeper. You can't construct a
  `CardModel` without specifying `type`; you can't read `payloadJSON`
  without going through `cardType.decodePayload(from:)`.
- A unit test (`CardPayloadRoundtripTests`) enforces every CardType's
  payload encode/decode round-trip; CI rejects breakage.

**Alternatives considered**:

- One @Model per type + 7 optional relationships on CardModel: rejected
  — 7 nil-valued fields on every Card, plus 7 record types in CloudKit
  for what is logically 1 card kind.
- Giant CardModel with every field as optional: rejected — schema
  pollution, type partition leaked into storage.
- `@Attribute(.transformable)` with a custom NSValueTransformer:
  rejected — Obj-C bridge, Swift 6 concurrency friction, and CloudKit
  ends up storing `Data` anyway (transformer just shifts the work).

---

## R-6: Project generation

**Decision**: XcodeGen with `project.yml`. Local SPM packages for
`AIDashCore` and `AIDashUI`; XcodeGen-generated `.xcodeproj` for the app
and CLI targets.

**Alternatives considered**:

- **Tuist**: rejected — Swift DSL has higher cognitive overhead than
  YAML; the project has 4 targets, not 40; user is already fluent with
  XcodeGen (VitalStride, SAP).
- **Pure `Package.swift` workspace** (no .xcodeproj): rejected — the app
  target needs entitlements, Info.plist, signing identity, and asset
  catalogs that SPM cannot describe.
- **Hand-maintained `.xcodeproj`**: rejected — merge conflicts in
  `.pbxproj` are notorious; Multica agents editing the project in
  parallel will not survive.

---

## R-7: Test framework

**Decision**: Swift Testing (`@Test` macro) for all `AIDashCore` unit
tests. UI tests not required in v1 (Constitution §Testing).

**Why not XCTest**:
- Swift Testing has cleaner async support (no `XCTestExpectation`
  ceremony).
- Parametric tests via `@Test(arguments:)` are first-class — useful for
  "test all 7 CardType payloads round-trip".
- Apple positioning is unambiguous in OS 26: Swift Testing is the
  default for new code.

**Migration risk**: zero, since this is greenfield.

---

## R-8: Device identifier strategy

**Decision**: `device` field on `UserEvent` is generated by
`AIDashCore/DeviceID/DeviceIdentifier.swift`:

```swift
public enum DeviceIdentifier {
    public static func current() -> String {
        let name = readableName()        // OS-specific
        let suffix = stableUUID().prefix(8)
        return "\(name) [\(suffix)]"
    }
}
```

- iOS / iPadOS: `name = UIDevice.current.name`,
  `stableUUID = UIDevice.current.identifierForVendor!.uuidString`.
- macOS: `name = Host.current().localizedName` (or `ProcessInfo.processInfo.hostName`
  as fallback), `stableUUID = IORegistryEntry hardware UUID`.

**Examples**:
- `"Tianpli 的 iPhone [3F2A4B1C]"`
- `"Tianpli 的 MacBook Pro [9D17AE52]"`
- `"Tianpli 的 iPad Pro [B4F8120D]"`

**Why combined**: agents reading reports want human-readable names; agents
joining historical events across device renames want a stable suffix.

**Alternatives considered**:
- Pure UUID: agents have to maintain a "UUID → friendly name" map
  themselves; UI display is opaque.
- Pure name: breaks history if user renames device.
- iCloud-derived device-id: requires extra CloudKit query, no upside
  over `identifierForVendor`.

---

## R-9: CI strategy

**Decision**: GitHub Actions hosted macOS runner (`macos-latest`, ≥ 26)
as primary CI. Document a self-hosted runner fallback in this file for
when free-tier quota is at risk.

**Cost math**:
- Free tier on private repos: 2000 Linux minutes/month, macOS = 10x =
  200 macOS minutes/month effective.
- This project's per-PR CI run: ~4–5 minutes.
- Sustainable rate without paying: ~40 PRs/month. Project will not
  approach this.
- If it does, $0.08/macOS-minute beyond the free quota.

**Self-hosted fallback** (no code change required; only
`.github/workflows/ci.yml` edit):

```yaml
jobs:
  build-and-test:
-    runs-on: macos-15
+    runs-on: [self-hosted, macOS, ARM64]
```

The user's Mac runs `actions-runner` as a launchd service. Token
provisioning is a one-time `gh api` call. This swap is documented but
not pre-installed because it's pure dead weight until needed.

**Why not Xcode Cloud**: tighter Apple Account coupling, less flexible
matrix, less mature for non-app targets (like our CLI).

---

## R-10: Briefing retention

**Decision**: Briefing records older than 90 days are deleted from
CloudKit Private DB automatically by the app. Cleanup runs:
- On every app launch (in a low-priority Task).
- On a 24h background timer while the app is running.

UserEvent records cascade-delete with their parent CardModel via
SwiftData `@Relationship(deleteRule: .cascade)`.

**Why 90 days**:
- Spec D18 keeps "today only" UI in v1; deeper history is v2 work on the
  same schema. 90 days provides 3 months of v2-ready data without manual
  user intervention.
- CloudKit Private DB free quota: 5 GB. At ~50 KB per briefing × 90 days
  = 4.5 MB used. Three orders of magnitude under the limit.

**Why hardcoded in v1 (not user-configurable)**: matches spec D14's
preference against UI-driven configuration and avoids one more setting
to forget. If the user later wants longer retention, it's a one-line
constant change.

---

## Resolved questions (sanity check against the spec)

- ✅ Spec FR-004 (CLI schema validation) — R-2 specifies local
  validation in CLI before XPC dispatch.
- ✅ Spec FR-005 (idempotency) — R-1's single-CloudKit-owner design
  ensures all writes flow through one place; idempotency by `id` is
  trivial in SwiftData (`@Attribute(.unique)`).
- ✅ Spec FR-015 (60s sync) — R-1's `NSPersistentCloudKitContainer`
  uses CloudKit's subscription push, typical < 10s in practice (R-9
  caveat: not an SLA).
- ✅ Spec FR-031 (forward compat on unknown fields) — R-5's
  JSONDecoder default behavior.
- ✅ Spec FR-040 (zero third-party server) — R-1 and R-9 keep all data
  on Apple infra; CI never touches CloudKit data.
- ✅ Spec FR-041 (graceful iCloud absence) — handled in app's CloudKit
  container setup error path; surfaces an actionable UI state.
- ✅ Spec SC-002 (60s cross-device sync) — Apple's documented typical
  push latency for Private DB; R-1's design uses subscriptions.
- ✅ Spec SC-005 (zero malformed records reach CloudKit) — R-2's
  defense-in-depth: validate at CLI, re-validate at app side, only
  then write to SwiftData.

---

## Open questions (deferred to /speckit-tasks or post-v1)

- **Q-O-1** (post-v1): When the v2 history-navigation UI ships, what's the
  swipe / pagination affordance? Spec D18 punted; tracked separately.
- **Q-O-2** (post-v1): Push notifications for "new briefing published"?
  CloudKit Subscriptions support this, but spec excludes from v1. Defer.
- **Q-O-3** (post-v1): Widget extensions (lock screen, StandBy)? Defer.
- **Q-O-4** (/speckit-tasks): Concrete folder for the bundled CLI binary —
  /usr/local/bin or ~/.local/bin? Affects PATH guidance in quickstart.
- **Q-O-5** (post-v1): Multiple iCloud accounts on one Mac (rare). Out of
  v1 scope per spec assumptions.
