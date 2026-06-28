# Contract: `aidash` CLI Surface

> Authoritative reference for every CLI subcommand. Agents read this AND
> `aidash --help` output (which is generated from `ArgumentParser` and
> mirrors this document). If the two ever disagree, the CLI binary is the
> source of truth.

---

## Global

```
aidash <subcommand> [options]
```

**Global flags** (all subcommands):

| Flag | Default | Meaning |
|---|---|---|
| `--json` | off | Emit machine-readable JSON on stdout instead of human format |
| `--quiet` | off | Suppress non-essential stdout (errors still go to stderr) |
| `--help, -h` | — | Print subcommand help and exit 0 |
| `--version` | — | Print CLI version, app version (if reachable), and exit 0 |

**Exit codes**:

| Code | Class | Agent retry hint |
|---|---|---|
| 0 | success | continue |
| 1 | local validation failed | do not retry; fix input |
| 2 | XPC transport failed (app unavailable, launch failed, 5s timeout) | retry with backoff |
| 3 | App-side error (CloudKit quota, conflict, schema drift) | inspect `error.code` |

**Error envelope on stderr** (always JSON, even without `--json`):

```jsonc
{
  "ok": false,
  "error": {
    "code": "schema.unknown_card_type",   // dotted; stable; parseable
    "message": "Card type 'unicorn' is not allowed.",
    "field": "type",                       // optional
    "got": "unicorn",                      // optional
    "allowed": ["metric", "insight", ...], // optional
    "requestId": "uuid"                    // for log correlation
  }
}
```

**Success envelope on stdout when `--json`**:

```jsonc
{
  "ok": true,
  "data": { /* subcommand-specific */ },
  "requestId": "uuid"
}
```

---

## `aidash briefing`

### `aidash briefing put`

Create or update a Briefing's top-level metadata. Idempotent by `--date`.

```
aidash briefing put --date <YYYY-MM-DD|today|yesterday>
                    --generated-by <agent-name>
                    [--published]
```

| Flag | Required | Notes |
|---|---|---|
| `--date` | yes | `YYYY-MM-DD`, or sugar `today`/`yesterday` resolved in local timezone |
| `--generated-by` | yes | Human-readable agent identifier, free-form |
| `--published` | no | Equivalent to `briefing put` then `briefing publish` in one call |

**Success data**: `{ "date": "...", "generatedAt": "...", "publishedAt": null }`.

### `aidash briefing publish`

Mark a briefing as visible to readers (atomic — spec FR-006).

```
aidash briefing publish --date <YYYY-MM-DD|today|yesterday>
```

**Success data**: `{ "date": "...", "publishedAt": "..." }`.

**Errors**:
- `briefing.not_found` (exit 3) — no Briefing record exists for that date.

### `aidash briefing get`

Read a Briefing (for agents to verify their writes or do reads).

```
aidash briefing get --date <YYYY-MM-DD|today|yesterday|latest>
```

**Success data**: full Briefing as JSON (containers + cards, payloads
decoded into their typed shapes). The Briefing envelope includes
`publishedAt` (ISO-8601 string, or `null` for an unpublished draft) so
callers can verify a prior `briefing publish` without inspecting the
store directly.

---

## `aidash container`

### `aidash container put`

Create or update a Container. Idempotent by `--id`.

```
aidash container put --briefing-date <YYYY-MM-DD|today|yesterday>
                     --id <uuid>
                     --title <string>
                     [--subtitle <string>]
                     --order <int>
                     [--layout auto|list|grid|hero]
                     [--style neutral|success|warning|accent]
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--briefing-date` | yes | — | The briefing this container belongs to |
| `--id` | yes | — | Caller-supplied UUID |
| `--title` | yes | — | Agent-chosen container heading |
| `--subtitle` | no | nil | Optional secondary heading |
| `--order` | yes | — | Sparse int (10, 20, 30...) |
| `--layout` | no | `auto` | Container rendering hint |
| `--style` | no | `neutral` | Visual style |

**Errors**:
- `briefing.not_found` (exit 3) — referenced briefing doesn't exist; call
  `briefing put` first.
- `schema.invalid_layout` / `schema.invalid_style` (exit 1).

### `aidash container delete`

```
aidash container delete --id <uuid>
```

Cascades to all child cards.

---

## `aidash card`

### `aidash card put`

Create or update a Card. Idempotent by `--id`.

```
aidash card put --container-id <uuid>
                --id <uuid>
                --type <CardType>
                --size <CardSize>
                [--style <CardStyle>]
                --payload <json-string | @file.json>
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--container-id` | yes | — | Parent container's UUID |
| `--id` | yes | — | This card's UUID |
| `--type` | yes | — | See full list below |
| `--size` | yes | — | `small \| medium \| wide \| hero` |
| `--style` | no | `neutral` | `neutral \| success \| warning \| accent` |
| `--payload` | yes | — | Either inline JSON string, or `@path/to/file.json` |

**Valid CardType values** (validated locally; CLI rejects unknown):
- `metric`
- `insight`
- `agentSummary`
- `todoList`
- `trending`
- `digest`
- `sectionHeader`

**Per-type payload schemas**: see [cardtype-payloads.md](./cardtype-payloads.md).

**Errors**:
- `schema.unknown_card_type` (exit 1) — `--type` value not in whitelist.
  Error envelope includes `allowed: [...]`.
- `schema.unknown_card_size` / `schema.unknown_card_style` (exit 1).
- `schema.payload_decode_failed` (exit 1) — payload JSON doesn't match
  the type's expected struct. Error includes `field` of the first
  decode failure.
- `schema.payload_too_large` (exit 1) — payload > 256 KB.
- `container.not_found` (exit 3) — referenced container doesn't exist.

### `aidash card delete`

```
aidash card delete --id <uuid>
```

---

## `aidash events`

### `aidash events pull`

Read user events for agent consumption. Stateless — agents track their own
high-water mark.

```
aidash events pull --since <ISO-8601-timestamp | YYYY-MM-DD | "yesterday">
                   [--until <same formats>]
                   [--card-id <uuid>]
                   [--action done|star]
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--since` | yes | — | Lower bound (inclusive). Local timezone for date-only |
| `--until` | no | "now" | Upper bound (exclusive) |
| `--card-id` | no | all cards | Filter by single card |
| `--action` | no | all actions | Filter by action type |

**Output (always JSON, even without `--json`)** — newline-delimited:

```jsonl
{"id":"...","timestamp":"2026-06-23T09:15:23Z","device":"...","cardId":"...","action":"done"}
{"id":"...","timestamp":"2026-06-23T09:15:24Z","device":"...","cardId":"...","action":"star"}
```

When `--json` flag is set, output is a single array instead:

```jsonc
{
  "ok": true,
  "data": {
    "events": [
      { ... },
      { ... }
    ],
    "count": 2
  }
}
```

**Ordering** (per spec FR-024): events sorted by
`(timestamp, device, cardId)` lexicographic. Stable and deterministic.

---

## `aidash schema`

### `aidash schema list`

Print the full schema as JSON. Agents can call this once at startup to
self-document.

```
aidash schema list [--type <CardType>]   # filter to one type
```

**Output**:

```jsonc
{
  "ok": true,
  "data": {
    "cliVersion": "1.0.0",
    "schemaVersion": "1.0.0",
    "cardTypes": ["metric", "insight", ...],
    "cardSizes": ["small", "medium", "wide", "hero"],
    "cardStyles": ["neutral", "success", "warning", "accent"],
    "containerLayouts": ["auto", "list", "grid", "hero"],
    "userEventActions": ["done", "star"],
    "payloads": {
      "metric": { /* JSON schema for MetricPayload */ },
      "insight": { /* JSON schema for InsightPayload */ },
      ...
    }
  }
}
```

The `payloads.<type>` value is a JSON Schema draft-07 description suitable
for agent-side validation (the same agent might want to validate before
shelling out to `aidash`).

---

## End-to-end example

```bash
#!/bin/bash
# Morning briefer agent: publishes a briefing with two containers

set -e
ID() { uuidgen | tr 'A-Z' 'a-z'; }

# 1. Create today's briefing
aidash briefing put --date today --generated-by "morning-briefer"

# 2. Container 1: yesterday's wins
C1=$(ID)
aidash container put \
  --briefing-date today --id "$C1" \
  --title "Yesterday" --order 10 --layout list --style success

aidash card put \
  --container-id "$C1" --id $(ID) \
  --type metric --size medium \
  --payload '{"items":[
    {"label":"PRs merged","value":3,"trend":"up"},
    {"label":"Issues closed","value":7,"trend":"up"}
  ]}'

aidash card put \
  --container-id "$C1" --id $(ID) \
  --type digest --size hero \
  --payload '{"title":"Yesterday in review","body":"Made it through 3 PRs and the Sapphire integration test suite. Started planning Q3 architecture review."}'

# 3. Container 2: today's outline
C2=$(ID)
aidash container put \
  --briefing-date today --id "$C2" \
  --title "Today" --order 20 --layout auto

aidash card put \
  --container-id "$C2" --id $(ID) \
  --type todoList --size wide \
  --payload @/tmp/today-todos.json

# 4. Atomic publish — only now does the briefing become visible
aidash briefing publish --date today

# 5. Later: pull user events to learn for tomorrow
aidash events pull --since yesterday > /tmp/events.jsonl
```

---

## Notes for implementers

- All UUIDs MUST be canonical RFC 4122 (8-4-4-4-12 hex). CLI validates
  format locally.
- Timestamps are always ISO-8601 with timezone, UTC preferred for
  outputs. `today`/`yesterday` sugar resolves in the user's local
  timezone.
- Dates are always `YYYY-MM-DD` in user's local timezone (the
  "briefing date" is a calendar day, not a UTC instant).
- The CLI never reads `stdin` for content; payloads come from `--payload`
  arg or `@file` reference.
