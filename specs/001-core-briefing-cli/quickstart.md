# Quickstart — AIDash for Agents

> Minimal recipe for an agent author to publish a briefing. Read once;
> reference [`contracts/cli-surface.md`](./contracts/cli-surface.md) and
> [`contracts/cardtype-payloads.md`](./contracts/cardtype-payloads.md) for
> details.

---

## Prerequisites

- macOS 26+
- AIDash app installed at `/Applications/AIDash.app` (it auto-installs
  its own launchd agent on first run).
- `aidash` CLI on `$PATH` (e.g. `/usr/local/bin/aidash`).
- iCloud signed in (CloudKit is the storage backend).

Verify:

```bash
aidash --version
# → aidash 1.0.0 (app: 1.0.0, connected)
```

If you see `app: not running`, the CLI couldn't reach the app's XPC
service. The next CLI command will auto-launch the app (5s timeout).
You can also `open -a AIDash` manually.

---

## Five-minute recipe: publish a daily briefing

```bash
#!/bin/bash
set -e

# UUID helper (works on macOS)
ID() { uuidgen | tr 'A-Z' 'a-z'; }

# 1. Create today's briefing metadata
aidash briefing put --date today --generated-by "my-agent"

# 2. Add a container for "Yesterday"
C_YDAY=$(ID)
aidash container put \
  --briefing-date today \
  --id "$C_YDAY" \
  --title "Yesterday" \
  --order 10 \
  --layout list

# 3. Add a metric card inside it
aidash card put \
  --container-id "$C_YDAY" \
  --id $(ID) \
  --type metric --size medium --style success \
  --payload '{"items":[
    {"label":"Tasks done","value":7,"trend":"up"},
    {"label":"Focus hours","value":4.5,"unit":"h"}
  ]}'

# 4. Add a digest card (the day's narrative)
aidash card put \
  --container-id "$C_YDAY" \
  --id $(ID) \
  --type digest --size hero \
  --payload '{
    "title":"Yesterday in review",
    "body":"A productive day spent finishing the Sapphire integration. Three PRs merged, no incidents. Tomorrow looks lighter."
  }'

# 5. Atomic publish — only now does the briefing become visible
aidash briefing publish --date today
```

Open AIDash from the menubar → today's briefing should be there.

---

## Inspect what you published

```bash
aidash briefing get --date today --json | jq
```

---

## Pull user feedback to learn for tomorrow

When the user taps "done" or "star" on a card, an event is written. Your
agent should pull these to inform tomorrow's briefing:

```bash
aidash events pull --since yesterday --json | jq
```

Output:
```jsonc
{
  "ok": true,
  "data": {
    "events": [
      {
        "id": "...",
        "timestamp": "2026-06-23T09:15:23Z",
        "device": "Tianpli 的 iPhone [3F2A4B1C]",
        "cardId": "<card-uuid-from-step-3>",
        "action": "star"
      }
    ],
    "count": 1
  }
}
```

Your agent decides what to do with this signal. Common patterns:
- A `star` on a metric card → make that metric a recurring fixture.
- A `done` on a todoList item → exclude that item from tomorrow's todos.
- Repeated `star`s on insight cards from a particular source → write
  more insights from that source.

The app does **not** modify briefing content based on these events —
your agent is in charge of how feedback shapes future briefings.

---

## Schema discovery (CLI-as-self-documentation)

```bash
aidash schema list --json | jq
```

This returns every legal CardType, CardSize, CardStyle, ContainerLayout,
UserEventAction, plus a JSON Schema document for each CardType's
payload. Use this to dynamically validate before shelling out, or to
pretty-print "what kinds of cards can I produce."

---

## Error handling for agents

The CLI exits with one of four codes:

| Code | Meaning | What your agent should do |
|---|---|---|
| 0 | success | continue |
| 1 | input validation failed | **do not retry** — fix the input. The error JSON tells you what to fix |
| 2 | XPC transport failed (app unavailable) | retry with backoff |
| 3 | app-side error (CloudKit quota, conflict) | inspect `error.code` |

The error envelope on stderr is always JSON:

```jsonc
{
  "ok": false,
  "error": {
    "code": "schema.unknown_card_type",
    "message": "Card type 'unicorn' is not allowed.",
    "field": "type",
    "got": "unicorn",
    "allowed": ["metric","insight","agentSummary","todoList","trending","digest","sectionHeader"],
    "requestId": "..."
  }
}
```

Bash skeleton for robust agent invocation:

```bash
attempt() {
  local n=0
  while (( n < 3 )); do
    if out=$(aidash "$@" 2>err); then
      echo "$out"
      return 0
    fi
    local code=$?
    case $code in
      1)
        echo "Input rejected, NOT retrying:" >&2
        cat err >&2
        return 1
        ;;
      2)
        echo "Transport failure, retry $((++n))/3..." >&2
        sleep $((n * 2))
        ;;
      *)
        echo "App-side error (exit $code):" >&2
        cat err >&2
        return $code
        ;;
    esac
  done
  echo "Gave up after 3 transport retries" >&2
  return 2
}

attempt briefing put --date today --generated-by my-agent
```

---

## Idempotency: you can replay safely

Every `put` command is idempotent by its `--id`:

- Re-running `briefing put --date today --generated-by X` updates
  `generatedAt` and `generatedBy` but does not duplicate.
- Re-running `container put --id <fixed-uuid> ...` overwrites that
  container's title/subtitle/order/layout/style without touching cards.
- Re-running `card put --id <fixed-uuid> ...` overwrites that card's
  type/size/style/payload.

This means an agent's "regenerate today's briefing" routine can run any
number of times during the day without producing duplicates — as long
as it uses stable UUIDs for the same logical content.

Recommendation: derive UUIDs deterministically (e.g.
`UUIDv5(namespace="aidash", name="agent-summary-2026-06-23-multica")`)
so a re-run of the same generation logic produces the same UUIDs.

---

## Common agent patterns

### Daily cron at 06:30

```cron
30 6 * * * /usr/local/bin/my-agent --briefing-date today
```

The agent:
1. Collects yesterday's git activity, PR merges, calendar events,
   trending RSS, etc.
2. Composes containers and cards.
3. Calls `aidash` to publish.
4. Calls `aidash events pull --since 7d` to retrieve user feedback
   from the past week, feeds back into tomorrow's content selection.

### Per-agent summary card

If you run multiple specialist agents (e.g. one for code, one for
trending news, one for finance), each agent owns a single
`agentSummary` card in a shared "Agents" container. They use stable
UUIDs derived from their agent name + date.

### Incremental updates throughout the day

Nothing forbids calling `aidash card put` later in the day to update an
existing card. The app re-renders within seconds. Just keep the same
`--id`. You can also `aidash card delete --id ...` to remove a card the
user no longer needs.

---

## What's NOT supported in v1

- Reading historical briefings from the app (UI only shows today + most
  recent). The CLI's `briefing get --date 2026-06-15` works for
  diagnostics.
- `hide` action on cards (spec D17; deferred to v2).
- Push notifications on new briefing (spec assumption).
- Widget extensions (spec assumption).
- Streaming events (no `events watch` command; pull is the only mode).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `aidash --version` shows `app: not running` | App not auto-launched yet | `open -a AIDash` once |
| All commands exit 2 with `xpc.app_launch_failed` | App may be installed but not signed correctly | Reinstall AIDash.app |
| `cloudkit.account_unavailable` | iCloud not signed in | System Settings → Apple ID → Sign In |
| Briefing published on Mac, not visible on iPad | CloudKit sync delay (typical <60s) | Wait, or check iPad's iCloud sign-in |
| `schema.payload_too_large` | Payload > 256 KB | Split into multiple cards or summarize |
| User events not reaching your agent | Verify with `aidash events pull --since 1h` — if empty, check user actually tapped done/star on a real device | App may have queued events offline; they sync when device returns online |
