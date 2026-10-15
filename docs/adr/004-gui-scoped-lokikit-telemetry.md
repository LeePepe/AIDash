# ADR-004: Scope LokiKit Telemetry to GUI App Composition

## Status

Accepted for planning under constitution 1.14.0; implementation remains gated
by merge of the constitution amendment and REL-001 dependency resolution.

## Context

AIDash currently has no product telemetry. The accepted product-onboarding plan requires one AIDash-owned action signal and one ready-scene performance signal delivered through the reviewed Blob transport. Constitution 1.14.0 narrowly authorizes explicit-consent GUI telemetry and its isolated store while preserving briefing/UserEvent CloudKit rules; the constitution also requires this ADR for the non-Apple dependency.

LokiKit provides the required generic privacy, persistence, immutable retry, and Blob transport contract. It also declares newer Apple deployment floors and uses Swift concurrency/networking behavior that must not leak into AIDashCore, AIDashUI, CLI, headless XPC, or test-host modes. The accepted `v0.2.0` release identity was not resolvable at planning time, so REL-001 remains an implementation dependency gate.

ADR-003 separately governs a future sandboxed fixed install. Its fixed entitlements intentionally omit network-client access. Product telemetry must not silently change that decision.

## Decision

- Add LokiKit by one immutable approved revision/version only after REL-001 is satisfied; no branch or floating range is allowed.
- Link the product only to the GUI app and hostless `AIDashAppLogicTests` target through `project.yml`.
- Keep AIDashCore, AIDashUI, CLI, headless XPC composition, and test-host composition dependency-free and behaviorally unchanged.
- Add the GUI Settings toggle **Send usage data** as the sole consent authority
  on macOS and iOS/iPadOS. Persist it through app `UserDefaults.standard`;
  missing is false. Production CLI, headless/XPC, and test-host modes never construct the
  telemetry service.
- On first opt-in from the exact never-opted state, create and persist one
  random install UUID, then persist monotonic non-identity
  `telemetry.identityEstablished = true` before consent becomes active. Reuse
  the UUID and retain the marker across launches and consent cycles for the
  app's lifetime. A post-opt-in missing/malformed UUID or inconsistent
  marker/UUID/consent combination fails closed and never generates a
  replacement. Do not reuse
  `AIDashCore.DeviceIdentifier` or derive identity from device/hardware/account
  data.
- Construct the service at the existing app-mode seam only after persisted
  consent and validated manual host-key reads. First opt-in may persist its
  UUID/established-marker/consent preferences before config validates, but
  invalid config or established-preference inconsistency creates no service,
  store, uploader, timer, or network work.
- Use the direct Blob initializer, a Blob-only store, product-local privacy
  allowlist and persisted random UUID provider, and `heartbeatVersion: nil`.
  The bundle convenience initializer and SDK-owned startup/daily timers are
  forbidden.
- Emit only the two events, triggers, typed properties, monotonic formula,
  sampling, and lifecycle cardinality in
  `specs/007-product-telemetry-blob/contracts/aidash-events.md`.
- Turning consent off persists false, closes admission, disables/cancels active
  delivery, then awaits quiescence. No pending upload starts/continues; an
  ambiguous in-flight batch stays retained/unconfirmed with the store/install
  ID/history. Re-enable is fresh consent and resumes eligible retained work
  under the same install UUID.
- Version 1 has no install-ID Reset or rotation surface. A future Reset is a
  separate LokiKit SDK feature and product decision. AIDash must not add a
  shared-telemetry API for it or infer identity by parsing private catalog
  storage. Dependency rollback uses the same disable/cancel/quiesce/retain
  order and leaves the persisted install UUID unchanged.

## Build and platform cost

- XcodeGen resolves one additional remote Swift package for app and logic-test targets; package fetch/build increases cold CI time and binary size.
- AIDash retains its existing platform declarations. Wiring must not broaden LokiKit into packages/targets whose platform matrix differs.
- macOS and iOS app builds remain required in CI. Hook-owned local evidence may use `AIDashAppLogicTests`; host-based `AIDashAppTests` remain prohibited locally.
- REL-001 must publish the exact release/revision identity before `project.yml` is changed. Generated `AIDash.xcodeproj` is evidence only and remains untracked.

## Concurrency and lifecycle cost

- The app-local preferences/coordinator seam owns consent, the lifetime-stable
  install ID, monotonic established marker, explicit preference-state model,
  service lifetime, and at-most-once eligible GUI lifecycle state.
- View-layer entry remains `@MainActor`; transport/store work stays inside LokiKit's structured concurrency boundary.
- No `nonisolated(unsafe)`, `@unchecked Sendable`, detached task, or global actor escape is authorized by this ADR. A need for one requires a separate ADR.
- Disable persists consent false and disables/cancels delivery before awaiting
  quiescence. Disable/re-enable never rotates the install ID, erases durable
  pending state or the established marker, or rewrites a frozen identity/path.

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
6. **Reuse DeviceIdentifier as install ID** — rejected: it may expose
   device/hardware identity and can exist before explicit opt-in.
7. **Expose install-ID Reset in version 1** — rejected by the replacement
   `no-reset-v1` decision: no current need justifies shared-SDK surface or
   private catalog inspection. Revisit it only as its own SDK feature.

## Consequences

- AIDash gains a narrow, reversible GUI producer with explicit cost and lifecycle ownership.
- The feature cannot implement until the constitution 1.14.0 amendment is
  published and merged via `constitution: authorize explicit-consent GUI telemetry`.
- Project/release wiring spans XcodeWorkspace and RepoInfra and must be delivered as separate layer-owned packets.
- Rollback ordering is compensating: first quiesce/retain in AIDashApp, then remove XcodeWorkspace/RepoInfra wiring.
- Any dependency identity change, mode expansion, heartbeat, install-ID Reset,
  fixed-install network change, or durable-store deletion requires a
  superseding ADR/review.
