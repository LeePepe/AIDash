# Contract-sync — keeping aidata payloads ↔ AIDash schema aligned

The XPC seam ships **untyped JSON**. Nothing at compile time catches a mapper that
emits a field the payload struct doesn't declare, or a required field the mapper
forgets. Drift is silent until a card fails to decode (→ CardRouter fallback
placeholder) or renders blank. This check closes that gap.

## What must agree, per CardType

For each `CardType` raw value (e.g. `metric`, `trending`):

1. **aidata mapper** (`L5_apps/digest/aidash.py`) emits `type="<t>"` somewhere.
2. **Core enum** (`CardType.swift`) has the case + a `decode` arm.
3. **Schema advertisement** (`XPCHandlers.payloadSchemas`) has a JSON Schema entry.
4. **Renderer** (`CardRouter.swift`) has a `case let p as <Type>Payload` arm.

A type present in one place but missing in another = drift. Directions:

- In mapper but NOT in enum/router → the app can't decode it → **CardRouter
  fallback** ("Card unavailable"). Fix: add the type on the Swift side (Playbook E)
  or stop emitting it.
- In enum/router but NOT in mapper → dead render path (harmless, but note it).
- Payload has a `required` field the mapper never sets → decode fails at runtime.
  Fix: either make the field optional in the payload + schema, or have the mapper
  always emit it.

## Field-level drift

For an existing card you reshaped:

- **New optional field** added to `<Type>Payload.swift` → must also be added to the
  `payloadSchemas` JSON Schema string (as a property, NOT in `required`) and to the
  `cardtype-payloads.md` mirror. Optional keeps old app builds compatible.
- **New required field** → dangerous: it breaks old payloads AND requires the mapper
  to always emit it. Prefer optional. If truly required, it's effectively a schema
  version bump — bump `schemaVersion` in `XPCHandlers` and coordinate both repos in
  lockstep.
- **Field the mapper emits but no payload declares** → silently dropped by Codable.
  Not a crash, but the data never renders. Add it to the payload + schema.

## Running the check

```bash
bash .claude/skills/aidash-content/scripts/contract_check.sh
```

It greps both repos and reports, per CardType, presence in the four places, plus a
heuristic scan of each payload's `required` fields vs. what the mapper emits. It is
a **lint, not a proof** — a PASS means no obvious structural drift; you still verify
real rendering in Step 4.

## When schemas legitimately diverge

Sometimes aidata intentionally emits a field before the Swift render lands (the
`delta`/`category`/`reason` radar rollout did this — pushed early, rendered later,
safe because Codable ignores unknown keys). That's fine **as long as the field is
optional on both sides**. Document the intent in the commit so the "in mapper, not
in router-render-yet" state reads as deliberate, not drift.
