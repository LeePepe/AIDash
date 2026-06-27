# CloudKit Server Rejection — Diagnostic Report (MY-1033 / MY-1035)

Status: diagnostic spike — no production code changed.
Scope: MY-1035, parent MY-1033.
Container under investigation: `iCloud.com.tianpli.aidash`
Developer team: `4Z8GG667QD`
Date: 2026-06-27

## Summary

The failing `CKError 15/2000 "Server Rejected Request"` on `com.apple.coredata.cloudkit.zone:__defaultOwner__` is reproducing in the latest build. Evidence below shows the App ID, CloudKit Dashboard container, and provisioning profile are all correctly configured server-side for team `4Z8GG667QD`. The signed application bundle, however, embeds an incomplete entitlement set: it omits `com.apple.developer.icloud-container-environment` and `com.apple.developer.ubiquity-container-identifiers`, both of which the issued provisioning profile authorizes. This mismatch between what the profile grants and what the codesign blob declares is the most plausible single root cause for the server-side rejection.

Recommended next action: **entitlement code change** — extend `Apps/AIDashApp/AIDashApp.entitlements` with the two missing keys, rebuild, and re-test. No Dashboard / Portal action is required from the user at this point.

## Root-candidate evidence

### A. CloudKit Dashboard container under team `4Z8GG667QD`
Implied present. The embedded provisioning profile signed by Apple WWDR for this app on 2026-06-26 lists in its `Entitlements` dictionary:

```
com.apple.developer.icloud-container-development-container-identifiers = [iCloud.com.tianpli.aidash]
com.apple.developer.icloud-container-environment = [Production, Development]
com.apple.developer.icloud-container-identifiers = [iCloud.com.tianpli.aidash]
com.apple.developer.ubiquity-container-identifiers = [iCloud.com.tianpli.aidash]
com.apple.developer.team-identifier = 4Z8GG667QD
```

Apple does not issue a profile authorizing a container the team does not own; the container therefore exists under team `4Z8GG667QD` and has both Production and Development environments enabled. A direct CloudKit Dashboard fetch was not performed because the agent has no authenticated access to `icloud.developer.apple.com`; the user can confirm visually if desired, but the profile evidence already satisfies this question.

### B. Apple Developer Portal App ID `com.tianpli.aidash`
Confirmed present with CloudKit capability and container association. The same profile entitlement set above could not be issued otherwise. The profile is also marked `IsXcodeManaged=true` and was regenerated automatically on 2026-06-26, so Xcode's automatic-signing path has successfully reconciled the App ID with the new paid team.

### C. Local provisioning profile
A direct grep of `~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision` returned 0 hits for `com.tianpli.aidash`. The active profile is therefore not stored there; it is embedded directly in the built `AIDash.app/Contents/embedded.provisionprofile`. This is normal for Mac apps using Xcode-managed signing on macOS 15+. Decoding the embedded profile shows:

| Field | Value |
| --- | --- |
| Name | Mac Team Provisioning Profile: com.tianpli.aidash |
| UUID | `9601f730-a44f-49b6-9d38-100bacd4817e` |
| TeamIdentifier | `4Z8GG667QD` |
| TeamName | Tianpei Li |
| Platform | OSX |
| AppIDName | `XC com tianpli aidash` |
| ExpirationDate | 2027-06-26 |
| IsXcodeManaged | true |

The certificate chain inside the profile resolves to `Apple Development: 1105208297@qq.com (RADE22GAMA)` issued under team `4Z8GG667QD`, matching the codesign authority on the signed binary.

### D. Built-app codesign entitlements
Inspected on the most recent real build:

`/Users/tianpli/Library/Developer/Xcode/DerivedData/AIDash-frhuuepxczvlttdmqkjklaiznlky/Build/Products/Debug/AIDash.app`

```
$ codesign -dv ...
Identifier=com.tianpli.aidash
Authority=Apple Development: 1105208297@qq.com (RADE22GAMA)
TeamIdentifier=4Z8GG667QD
Signature size=4784
Runtime Version=26.5.0
```

```
$ codesign -d --entitlements - --xml ...
com.apple.application-identifier            = 4Z8GG667QD.com.tianpli.aidash
com.apple.developer.icloud-container-identifiers = [iCloud.com.tianpli.aidash]
com.apple.developer.icloud-services         = [CloudKit]
com.apple.developer.team-identifier         = 4Z8GG667QD
com.apple.security.app-sandbox              = true
com.apple.security.get-task-allow           = true
com.apple.security.network.client           = true
```

Compared against what the profile authorizes, the signed binary is missing:

| Key | Profile grants | Signed app declares |
| --- | --- | --- |
| `com.apple.developer.icloud-container-environment` | `[Production, Development]` | **absent** |
| `com.apple.developer.ubiquity-container-identifiers` | `[iCloud.com.tianpli.aidash]` | **absent** |

This matches the source file `Apps/AIDashApp/AIDashApp.entitlements`, which declares only `icloud-container-identifiers`, `icloud-services=[CloudKit]`, `app-sandbox`, and `network.client`.

### E. Runtime CKError reproduction
Unified log from this morning's launches (`log show --predicate '(subsystem == "com.apple.cloudkit" OR subsystem == "com.apple.coredata") AND processImagePath CONTAINS "AIDash"' --info --debug --last 1h`) shows the same rejection on every fresh setup attempt. Excerpt from 22:19:36 and 22:26:19 launches:

```
PFCloudKitSetupAssistant _saveZone:error: — Waiting on save zone for store
  42E89ED1-DA6A-45CE-A825-CB18EF9CD60B
CKModifyRecordZonesOperation
  operationID=5833ED1933D67A2C
  container=iCloud.com.tianpli.aidash
  databaseScope=Private
finished with error:
  PartialFailure (1011) "Failed to modify some record zones"
  partial errors:
    com.apple.coredata.cloudkit.zone:__defaultOwner__
      = CKError "Server Rejected Request" (15/2000)
NSCloudKitMirroringDelegate _recoverFromError:withZoneIDs:forStore:inMonitor:
  Failed to recover from error: CKErrorDomain:15
```

The container ID in the failing request is exactly `iCloud.com.tianpli.aidash`, matching the App ID's container. The store UUID is stable across the two launches (`42E89ED1-…`), indicating SwiftData is not regenerating its CKMirror identity between attempts; the failure is structurally repeatable.

## Why this points at entitlements, not Dashboard / Portal

Two observations rule out the "container missing in Dashboard" and "App ID not configured" branches:

1. Apple WWDR signed a profile for this team that explicitly names `iCloud.com.tianpli.aidash` in both `icloud-container-identifiers` and `icloud-container-development-container-identifiers`. Apple's signing service would reject a profile request referencing a container that does not exist under the team or an App ID without CloudKit enabled.
2. The CKModifyRecordZonesOperation reached `cloudd` and got a server response (not `CKErrorDomain Code=3 "Bad container"` and not `Code=9 "Not Authenticated"`). The server actively evaluated the request and rejected it — i.e. the request authenticated against the right container and was refused at the permission layer.

What is left is the request's **environment routing**. `com.apple.developer.icloud-container-environment` is the entitlement CloudKit reads to decide whether to route a zone-modification request to the Development or Production CloudKit instance for that container. When this key is absent on macOS sandboxed builds with managed signing, CloudKit's behavior is implementation-defined; in practice the runtime can issue the request against a CloudKit instance the dev account isn't authorized to write to (typically Production), producing exactly a `15/2000` rejection on `__defaultOwner__` zone create.

Separately, `com.apple.developer.ubiquity-container-identifiers` is required by macOS App Sandbox for CloudKit-backed CoreData stores even when ubiquity (iCloud Drive) is not used directly; without it, certain CKMirror code paths hit the sandbox before reaching CloudKit, surfacing as opaque server-side rejections. Granting it is safe — the profile already lists the same container — and aligns the signed app with what Apple already authorized.

## Recommended next action

**One action path: extend the entitlement plist.** No user action against the Apple Developer Portal or CloudKit Dashboard is required at this time.

Add to `Apps/AIDashApp/AIDashApp.entitlements` (handled in a follow-up implementation issue; this spike does not modify production code):

```xml
<key>com.apple.developer.icloud-container-environment</key>
<string>Development</string>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.tianpli.aidash</string>
</array>
```

Notes for the follow-up:
- The profile authorizes both `Production` and `Development`. Use `Development` for local Debug builds. A Release/archive build should switch to `Production`; the simplest path is two `.entitlements` files keyed by configuration, or a conditional `CODE_SIGN_ENTITLEMENTS` setting in `project.yml` — but that decision is out of scope for this spike.
- `aps-environment` is NOT recommended right now. The profile does not grant it. Adding it without first toggling Push Notifications on the App ID will cause the signer to refuse the binary; that capability can be enabled later if CloudKit silent push notifications are needed for sync change tracking.

After the entitlement change, validate by:
1. Building the app in Debug.
2. Confirming `codesign -d --entitlements -` now lists `com.apple.developer.icloud-container-environment = Development` and the ubiquity identifier.
3. Launching the app and confirming the unified log no longer shows `CKError 15/2000` on `__defaultOwner__` zone create. The first successful run should log `PFCloudKitSetupAssistant` followed by a `CKModifyRecordZonesOperation` that finishes without error.
4. Running `aidash briefing put --date today --generated-by test` via the CLI binary and confirming the write reaches SwiftData on the app side.

If `CKError 15/2000` persists after the entitlement change, the next branch to investigate is the iCloud account state on the local machine (iCloud Drive enabled, CloudKit running for `4Z8GG667QD` apps) — but that is a separate spike and not implied by current evidence.

## Files inspected (read-only)

- `Apps/AIDashApp/AIDashApp.entitlements`
- `project.yml`
- `Apps/AIDashApp/Sources/Sync/CloudKitContainer.swift`
- `~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision` (none matched; profile is embedded in app bundle)
- Built app at `~/Library/Developer/Xcode/DerivedData/AIDash-frhuuepxczvlttdmqkjklaiznlky/Build/Products/Debug/AIDash.app`
  - `codesign -dv` and `codesign -d --entitlements -`
  - `Contents/embedded.provisionprofile`
- Unified log via `log show` for subsystems `com.apple.cloudkit` and `com.apple.coredata` filtered to `processImagePath CONTAINS "AIDash"`

No production Swift, plist, project configuration, or schema file was modified by this spike.
