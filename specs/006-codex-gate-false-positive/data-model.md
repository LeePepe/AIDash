# Data Model: Complete-Predicate Review Evidence

This feature introduces no persisted application, warehouse, or configuration
data model.

The only conceptual records are transient prompt-contract concepts:

| Concept | Fields | Lifetime |
|---|---|---|
| Validation claim | subject value, alleged result, cited deciding expression | One automated review |
| Complete predicate evidence | full expression, unions/defaults/normalization/negation, source location | One automated review |
| Review verdict | exact HEAD, pass/changes, blockers, notes | Existing gate lifecycle; unchanged |

No schema, migration, retention, or compatibility work is required.
