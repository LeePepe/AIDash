#!/bin/bash
# Rich sample briefing to exercise the modernized AIDash layout:
# grid layouts (multi-column), mixed sizes, all four styles, series/ratio
# data-viz, and multiple card types. Idempotent — stable UUIDs per logical
# card so re-runs overwrite rather than duplicate.
set -euo pipefail

AIDASH="$(find "$HOME/Library/Developer/Xcode/DerivedData/AIDash-"*/Build/Products/Debug -name aidash -type f 2>/dev/null | head -1)"
[ -n "$AIDASH" ] || { echo "aidash binary not found — build the CLI first" >&2; exit 1; }
echo "Using CLI: $AIDASH"

# Fixed UUIDs (deterministic → idempotent replay)
C_KPI="11111111-0000-0000-0000-000000000001"
C_ADO="11111111-0000-0000-0000-000000000002"
C_TODAY="11111111-0000-0000-0000-000000000003"
C_TREND="11111111-0000-0000-0000-000000000004"

card() { "$AIDASH" card put --quiet "$@"; }

# 1) Briefing shell
"$AIDASH" briefing put --date today --generated-by "sample-seed"

# ────────────────────────────────────────────────────────────────
# Container 1 — OVERVIEW: KPI grid (grid layout → multi-column),
# small cards each with a sparkline or ring gauge, mixed styles.
# ────────────────────────────────────────────────────────────────
"$AIDASH" container put --quiet --briefing-date today --id "$C_KPI" \
  --title "Overview" --order 10 --layout grid

card --container-id "$C_KPI" --id "22222222-0000-0000-0000-000000000001" \
  --type metric --size small --style success \
  --payload '{"items":[{"label":"PRs merged","value":12,"trend":"up","higherIsBetter":true,"context":"Sapphire · this week","series":[4,6,5,8,7,10,9,12]}]}'

card --container-id "$C_KPI" --id "22222222-0000-0000-0000-000000000002" \
  --type metric --size small --style neutral \
  --payload '{"items":[{"label":"Build time","value":124,"unit":"s","trend":"down","higherIsBetter":false,"context":"CI median · 7d","series":[180,170,165,150,148,140,132,124]}]}'

card --container-id "$C_KPI" --id "22222222-0000-0000-0000-000000000003" \
  --type metric --size small --style accent \
  --payload '{"items":[{"label":"Coverage","value":87,"unit":"%","ratio":0.87,"context":"Sapphire"}]}'

card --container-id "$C_KPI" --id "22222222-0000-0000-0000-000000000004" \
  --type metric --size small --style warning \
  --payload '{"items":[{"label":"Open incidents","value":3,"trend":"up","higherIsBetter":false,"context":"all repos · today","series":[0,1,1,2,1,2,3,3]}]}'

# ────────────────────────────────────────────────────────────────
# Container 2 — Yesterday: full-row digest + half-width insight (grid).
# Prose cards use grid + medium (2-up) so short cards pair side by side
# instead of stretching full-width into a sparse strip.
# ────────────────────────────────────────────────────────────────
"$AIDASH" container put --quiet --briefing-date today --id "$C_ADO" \
  --title "Yesterday in review" --order 20 --layout grid

card --container-id "$C_ADO" --id "33333333-0000-0000-0000-000000000001" \
  --type digest --size wide --style neutral \
  --payload '{
    "title":"A strong, incident-light day",
    "subtitle":"All repos · yesterday",
    "body":"Twelve PRs merged across Sapphire and Basalt, with the v9-blocking crash finally resolved. The design-system migration crossed 70%. Build times are trending down after the cache rework.",
    "sections":[
      {"heading":"Shipped","paragraphs":["SAP-301 crash fix (unblocks v9).","Cache rework cut CI ~30%."]},
      {"heading":"Blocking today","paragraphs":["Perf review feedback due 5pm.","Q3 priority decision pending."]}
    ]
  }'

card --container-id "$C_ADO" --id "33333333-0000-0000-0000-000000000002" \
  --type insight --size medium --style accent \
  --payload '{"title":"Build-cache rework is paying off","subtitle":"Sapphire CI · this week","body":"Median CI dropped from 180s to 124s over the week — the single biggest developer-time win this sprint. Consider extending the same cache strategy to the integration suite."}'

# ────────────────────────────────────────────────────────────────
# Container 3 — TODAY: todo + agent summary side by side (grid + medium).
# ────────────────────────────────────────────────────────────────
"$AIDASH" container put --quiet --briefing-date today --id "$C_TODAY" \
  --title "Today" --order 30 --layout grid

card --container-id "$C_TODAY" --id "44444444-0000-0000-0000-000000000001" \
  --type todoList --size medium --style warning \
  --payload '{"items":[
    {"title":"Reply to performance-review feedback","priority":"high"},
    {"title":"Decide Q3 priorities with staff+","priority":"high"},
    {"title":"Review VitalStride changelog","priority":"medium"},
    {"title":"Archive stale feature branches","priority":"low"}
  ]}'

card --container-id "$C_TODAY" --id "44444444-0000-0000-0000-000000000002" \
  --type agentSummary --size medium --style success \
  --payload '{"agentName":"Multica","completed":[
    {"title":"Merged 3 Sapphire PRs","ref":"SAP-297..301"},
    {"title":"Regenerated changelog"}
  ],"stats":[{"label":"PRs","value":3},{"label":"Reviews","value":9}]}'

# ────────────────────────────────────────────────────────────────
# Container 4 — TRENDING (list layout, scores as pills + sparkline).
# ────────────────────────────────────────────────────────────────
"$AIDASH" container put --quiet --briefing-date today --id "$C_TREND" \
  --title "Trending" --order 40 --layout list

card --container-id "$C_TREND" --id "55555555-0000-0000-0000-000000000001" \
  --type trending --size hero --style neutral \
  --payload '{"topic":"Swift / iOS","items":[
    {"title":"Swift 6.1 native macro caching","url":"https://swift.org","score":487},
    {"title":"SwiftData query-builder refactor","url":"https://example.com/a","score":312},
    {"title":"iOS 26.2 beta available","url":"https://example.com/b","score":205},
    {"title":"Xcode 27 preview","url":"https://example.com/c","score":150},
    {"title":"visionOS 3 SDK announced","url":"https://example.com/d","score":121}
  ]}'

# Atomic publish
"$AIDASH" briefing publish --date today
echo "✅ Sample briefing published. Open AIDash to view."
