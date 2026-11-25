# Skill quality contracts

The quality-gap path is an offline, metadata-only extension of aidata's L1–L5
pipeline. It is not a daily card or an app-side judge.

## Locked defaults

- `ACTIVE_SKILLS` is the explicit 26-package registry, including `agent-retro` and repository-local
  `aidash-content`; filesystem discovery never changes the denominator.
- Behavioral eligibility requires a valid registered skill, source/session/time,
  same-source prompt linkage, assistant activity, a closed 30-minute observation
  horizon, and source coverage. `max_tokens` invocations remain flagged but are
  excluded from first-pass satisfaction denominators. Missing evidence is
  `unknown`/`missing`, never zero.
- Correction classification is closed and deterministic (`negative_feedback`,
  `repair_request`, `repeat_request`, `reopen_edit`, `none`). Only bounded
  in-memory previews are inspected; L2–L5 retain class/confidence, version,
  lengths, hashes, and timestamps, never raw prompt/response text.
- Active duration sums adjacent activity gaps capped at 900 seconds. Edit churn
  is tool calls divided by assistant turns with a minimum denominator of one.
- The judge is an explicit offline runner. `--dry-run` is the default, network
  and cron are absent, and execution requires a caller-supplied local adapter.
  The component rubric scores are 0–3, the overall score is 1–5, and
  `pass_flag` requires `overall_score >= 4.0`. Adapter calls are bounded by
  timeout/output caps and single-flight execution; validated receipts replace
  the ignored L2 DB atomically.
- Judge eligibility is explicit: a skill is eligible only when it has at least
  one eligible invocation in the rolling 30-day window. `sampled` and `judged`
  count distinct eligible invocation IDs, so rejudges cannot push coverage over
  100%; `source_as_of` comes from persisted sample timestamps. `judged` means
  at least one valid, non-abstained verdict. A coverage result such as `4/19`
  is an honest denominator, not a 4/25 score.

The explicit operator command `./cli.py quality-behavior collect` followed by
`./cli.py quality-behavior normalize` materializes the Copilot projection; it
is not in `config.SOURCES` and is never launched by cron. The `quality/` L4
queries are read-only and rolling-window bounded. The normal L5 snapshot path
loads `quality_behavior` and `quality_judge` from the warehouse beside ROI
diagnostics; missing tables produce explicit missing/unknown rows.
