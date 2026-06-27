# Contract: XPC Protocol

> Authoritative reference for the XPC interface between the `aidash` CLI
> and the AIDash menubar app. Both sides import the same Codable structs
> from `AIDashCore/XPC/`.

---

## Service registration

- **Mach service name**: `com.tianpli.aidash.xpc.v1`
- **Listener side**: AIDash.app (macOS target only).
  - Registered via `NSXPCListener(machServiceName:)` on app launch.
  - Unregistered on app quit (graceful shutdown).
- **Client side**: `aidash` CLI binary.
  - Connects via `NSXPCConnection(machServiceName:)` per invocation.
  - Auto-launches AIDash.app via `NSWorkspace` if service is missing.

**Versioning**: `.v1` is part of the Mach service name. A breaking
protocol change ships a new name (`.v2`), letting old CLI and new app
coexist during a transition.

### Launchd integration (required)

`NSXPCListener(machServiceName:)` is a thin wrapper over `launchd`'s
mach-port brokering — it only works when the **launchd job that owns
the process** has the corresponding `MachServices` entry. Therefore:

- The bundled LaunchAgent plist at
  `Apps/AIDashApp/Resources/com.tianpli.aidash.plist` (copied into
  `Contents/Library/LaunchAgents/` at build) **MUST** declare:

  ```xml
  <key>MachServices</key>
  <dict>
      <key>com.tianpli.aidash.xpc.v1</key>
      <true/>
  </dict>
  ```

- The app's `Info.plist` MUST NOT declare `MachServices`. `Info.plist`
  `MachServices` only applies to XPC services bundled inside
  `Contents/XPCServices/`, not to launchd-managed agents — declaring
  it on the host app is misleading and unused.
- `SMAppService.agent(plistName:)` (used in `AIDashApp` launch) reads
  the LaunchAgent plist above; registration silently fails with
  `EX_CONFIG` (78) every `ThrottleInterval` seconds when `MachServices`
  is missing, because launchd has no port to broker to the CLI.

---

## Obj-C protocol

Defined in `AIDashCore/XPC/XPCProtocol.swift`. Single method —
everything else flows through the envelope inside `requestData`.

```swift
@objc public protocol AIDashXPCServiceProtocol {
    func execute(requestData: Data,
                 reply: @escaping (Data) -> Void)
}
```

**Why a single method**: see `research.md` §R-2. Summary: avoids Obj-C
type ceremony for every parameter, lets schema evolve without changing
the XPC interface signature, and recovers type safety in the Codable
envelope.

---

## Request envelope

```swift
public struct XPCRequest: Codable, Sendable {
    public let requestId: String       // UUID; for log correlation
    public let cliVersion: String      // CLI's version string
    public let command: String         // dotted: "card.put", "events.pull"
    public let params: Data            // command-specific Codable, encoded
}
```

**Command names** (full list — same scope as CLI surface):

| Command | Params struct | Reply data struct |
|---|---|---|
| `briefing.put` | `BriefingPutParams` | `BriefingPutResult` |
| `briefing.publish` | `BriefingPublishParams` | `BriefingPublishResult` |
| `briefing.get` | `BriefingGetParams` | `BriefingGetResult` (full Briefing) |
| `container.put` | `ContainerPutParams` | `ContainerPutResult` |
| `container.delete` | `ContainerDeleteParams` | empty |
| `card.put` | `CardPutParams` | `CardPutResult` |
| `card.delete` | `CardDeleteParams` | empty |
| `events.pull` | `EventsPullParams` | `EventsPullResult` |
| `schema.list` | empty | `SchemaListResult` |

Each Params/Result struct is defined in `AIDashCore/XPC/Commands/`.

### Example: `card.put`

```swift
public struct CardPutParams: Codable, Sendable {
    public let containerId: String
    public let id: String
    public let type: CardType
    public let size: CardSize
    public let style: CardStyle
    public let payload: Data           // already-validated JSON
}

public struct CardPutResult: Codable, Sendable {
    public let id: String
    public let updatedAt: Date
    public let wasCreated: Bool        // true if newly inserted, false if updated
}
```

---

## Response envelope

```swift
public struct XPCResponse: Codable, Sendable {
    public let requestId: String       // mirror request
    public let appVersion: String      // App's version string
    public let ok: Bool
    public let data: Data?             // command-specific Result, encoded; nil on error
    public let error: XPCError?        // nil on success
}

public struct XPCError: Codable, Sendable {
    public let code: String            // dotted; stable; see below
    public let message: String
    public let field: String?          // for schema errors: which field
    public let got: String?            // for schema errors: actual value
    public let allowed: [String]?      // for schema errors: valid values
    public let cause: String?          // optional underlying error description
}
```

---

## Error code taxonomy

All codes use dotted notation: `<category>.<reason>`. Stable across
versions — adding new codes is fine, removing/renaming is a breaking
change requiring a `.v2` Mach service.

### `schema.*` — input validation failures (mapped to CLI exit 1)

| Code | When |
|---|---|
| `schema.unknown_command` | `command` field not recognized by app |
| `schema.unknown_card_type` | CardType rawValue invalid |
| `schema.unknown_card_size` | CardSize rawValue invalid |
| `schema.unknown_card_style` | CardStyle rawValue invalid |
| `schema.unknown_container_layout` | ContainerLayout rawValue invalid |
| `schema.unknown_user_event_action` | UserEventAction rawValue invalid |
| `schema.invalid_uuid` | A UUID field is malformed |
| `schema.invalid_date` | Date string not parseable |
| `schema.payload_decode_failed` | Payload JSON doesn't match type's struct |
| `schema.payload_too_large` | Payload > 256 KB |
| `schema.missing_required_field` | A required field is missing |

### `briefing.*` / `container.*` / `card.*` — referential integrity (CLI exit 3)

| Code | When |
|---|---|
| `briefing.not_found` | Referenced briefing date doesn't exist |
| `briefing.already_published` | `briefing publish` called on already-published briefing — not an error, returns success silently. (Code reserved for future use if we ever want strict semantics) |
| `container.not_found` | Referenced container ID doesn't exist |
| `card.not_found` | Referenced card ID doesn't exist (for delete) |

### `cloudkit.*` — CloudKit problems (CLI exit 3)

| Code | When |
|---|---|
| `cloudkit.account_unavailable` | iCloud not signed in or account restricted |
| `cloudkit.network_unavailable` | Network failure during sync |
| `cloudkit.quota_exceeded` | User's iCloud quota full |
| `cloudkit.permission_denied` | Container permission issue |
| `cloudkit.unknown_error` | Anything else from CloudKit |

### `internal.*` — app-side bugs (CLI exit 3)

| Code | When |
|---|---|
| `internal.swiftdata_error` | SwiftData migration / corruption |
| `internal.unexpected` | Anything that shouldn't happen — should be logged |

---

## Lifecycle

### Happy path

```
CLI: NSXPCConnection(machServiceName: "com.tianpli.aidash.xpc.v1")
     conn.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
     conn.activate()
     conn.remoteObjectProxy.execute(requestData: encoded) { replyData in
         // decode XPCResponse, write to stdout/stderr, exit
     }
```

App side:

```swift
final class XPCService: NSObject, AIDashXPCServiceProtocol {
    func execute(requestData: Data, reply: @escaping (Data) -> Void) {
        Task {
            let response = await handle(requestData)
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }
}
```

### Sad path: app not running

```
CLI:    conn.activate(); proxy.execute(...) { ... }
        → NSXPCConnection.invalidationHandler fires
        → Error: Couldn't communicate with a helper application
        
CLI fallback:
        NSWorkspace.shared.openApplication(at: "/Applications/AIDash.app", ...)
        for attempt in 1...10:
            try? await Task.sleep(.milliseconds(500))
            if let conn2 = tryConnect(): break
        else:
            // 5s elapsed, give up
            stderr.write(XPCError(code: "xpc.app_unavailable", ...))
            exit(2)
```

### Sad path: app crashes mid-request

```
CLI:    proxy.execute(...) { ... }  ← reply never called
        invalidationHandler fires
        → exit 2 with error code "xpc.connection_invalidated"
```

### Sad path: app rejects with schema error

```
App:    XPCResponse(ok: false, error: XPCError(code: "schema.unknown_card_type", field: "type", got: "unicorn", allowed: ["metric", ...]))
CLI:    receives reply, decodes, writes error to stderr as JSON
        exit 1 (schema errors map to exit 1 even when surfaced via XPC,
                because the action the agent should take is identical:
                fix input, do not retry)
```

---

## Concurrency model

- The XPC `execute` method is called by the listener on a private serial
  queue. App side wraps in `Task { ... }` and dispatches handlers to the
  `@MainActor` for SwiftData access.
- All `XPCRequest`/`XPCResponse`/params/result structs are `Sendable`
  (enforced by Swift 6 strict concurrency).
- One CLI invocation = one XPC request = one response = one CLI process
  exit. No streaming or long-polling in v1.

---

## Versioning forward path

If a future change requires breaking the envelope (e.g. switching from
JSON to a binary format), the migration is:

1. Ship a new app version that registers BOTH `…xpc.v1` and `…xpc.v2`.
2. Ship a new CLI version that uses `…xpc.v2`.
3. After 1 release cycle with both, drop `…xpc.v1` from the app.

For additive changes within the envelope (new field on
`XPCRequest`/`XPCResponse`, new command, new error code), no versioning
is needed — Codable handles it gracefully (`decodeIfPresent`,
default-value initializers).
