# ADR-004: Scope LokiKit Telemetry to GUI App Composition

## Status

Accepted for planning; dependency resolution remains gated by REL-001.

## Context

AIDash currently has no product telemetry. The accepted product-onboarding plan requires one AIDash-owned action signal and one ready-scene performance signal delivered through the reviewed Blob transport. The constitution requires an ADR for a non-Apple dependency.

LokiKit provides the required generic privacy, persistence, immutable retry, and Blob transport contract. It also declares newer Apple deployment floors and uses Swift concurrency/networking behavior that must not leak into AIDashCore, AIDashUI, CLI, headless XPC, or test-host modes. The accepted `v0.2.0` release identity was not resolvable at planning time, so REL-001 remains an implementation dependency gate.

ADR-003 separately governs a future sandboxed fixed install. Its fixed entitlements intentionally omit network-client access. Product telemetry must not silently change that decision.

## Decision

- Add LokiKit by one immutable approved revision/version only after REL-001 is satisfied; no branch or floating range is allowed.
- Link the product only to the GUI app and hostless `AIDashAppLogicTests` target through `project.yml`.
- Keep AIDashCore, AIDashUI, CLI, headless XPC composition, and test-host composition dependency-free and behaviorally unchanged.
- Construct the service at the existing app-mode seam only after explicit consent and validated manual host-key reads.
- Use the direct Blob initializer, a Blob-only store, product-local privacy allowlist and nonpersonal UUID provider, and `heartbeatVersion: nil`. The bundle convenience initializer and SDK-owned startup/daily timers are forbidden.
- Emit only one product-local once-per-GUI-lifecycle action and one ready-scene performance event.
- Treat empty, unexpanded, or invalid config as a no-op before identity, storage, or network creation.
- On disable/rollback, await active flush exit and retain pending files plus historical identity epochs before removing dependency/config plumbing.

## Build and platform cost

- XcodeGen resolves one additional remote Swift package for app and logic-test targets; package fetch/build increases cold CI time and binary size.
- AIDash retains its existing platform declarations. Wiring must not broaden LokiKit into packages/targets whose platform matrix differs.
- macOS and iOS app builds remain required. Hostless tests run through `AIDashAppLogicTests`; host-based `AIDashAppTests` remain prohibited locally.
- REL-001 must publish the exact release/revision identity before `project.yml` is changed. Generated `AIDash.xcodeproj` is evidence only and remains untracked.

## Concurrency and lifecycle cost

- The app-local coordinator owns the service lifetime and exactly-once GUI lifecycle state.
- View-layer entry remains `@MainActor`; transport/store work stays inside LokiKit's structured concurrency boundary.
- No `nonisolated(unsafe)`, `@unchecked Sendable`, detached task, or global actor escape is authorized by this ADR. A need for one requires a separate ADR.
- Disable must quiesce work before dependency/config rollback; it must not erase durable pending state.

## Security and release injection

The endpoint and create-only writer SAS remain protected release inputs. Tracked build settings are empty. CI writes values only to a run-owned temporary xcconfig with verified mode `0600`; Fastlane/xcodebuild receive only its path. Fastlane `ensure` and workflow `if: always()` both remove it, and synthetic raw/shell-escaped sentinels must not appear in captured Release output.

An app plist is extractable and is not secret storage. This ADR relies on the separately approved create-only writer scope; it does not claim secrecy after shipping.

## Fixed-install boundary

This change does not edit ADR-003 or its fixed-install entitlements. A future sandboxed fixed install that emits telemetry needs a new decision about network-client entitlement and packaging. Until then, fixed-install telemetry is not claimed by this feature.

## Alternatives considered

1. **Put telemetry in AIDashCore** — rejected: it couples a domain package and CLI/headless paths to product delivery concerns.
2. **Use the bundle initializer** — rejected: implicit config and default heartbeat behavior cannot prove the required timer-free, fail-closed boundary.
3. **Use URLSession-only product code instead of LokiKit** — rejected: duplicates the reviewed persistence/privacy/retry contract and breaks shared-telemetry alignment.
4. **Wait for REL-001 before planning** — rejected: release identity gates dependency wiring and live proof, not the repository-native design.
5. **Change ADR-003 entitlements now** — rejected: fixed-install networking is outside scope and carries a distinct packaging/security decision.

## Consequences

- AIDash gains a narrow, reversible GUI producer with explicit cost and lifecycle ownership.
- Project/release wiring spans XcodeWorkspace and RepoInfra and must be delivered as separate layer-owned packets.
- Rollback ordering is compensating: first quiesce/retain in AIDashApp, then remove XcodeWorkspace/RepoInfra wiring.
- Any dependency identity change, mode expansion, heartbeat, fixed-install network change, or durable-store deletion requires a superseding ADR/review.
