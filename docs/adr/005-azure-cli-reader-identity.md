# ADR-005: Installed Azure CLI Boundary for Manual Blob Batch Collection

## Status

Accepted for the manual-batch plan. Implementation and live use remain gated by
their separately reviewed and authorized phases.

## Context

The selected scope is one human-authorized VoxPocket download using the Owner's
existing externally administered read/list-only Azure AD identity. Repository
code must not acquire or parse a token, implement Blob pagination, add per-object
state, or introduce an Azure SDK dependency. The external tool choice therefore
needs a stable architectural boundary without duplicating collector mechanics.

## Decision

The authorized human invokes the repository's dedicated Python `product-blob`
command. That command validates its one local URL/prefix pair and directly
invokes the already installed, pinned Azure CLI 2.91.0 for one
`az storage blob download-batch --auth-mode login --overwrite false`. Azure CLI
owns service listing and download behavior. Repository Python owns the privacy
environment, private staging, output validation, and one atomic completion
publication. It never runs `az login`, parses a token, selects another identity,
or adds a credential fallback.

GNU `gtimeout --signal=KILL 300s` is an external human-operator invocation
boundary only. It is not packaged by AIDash and is not a repository scheduler,
runner, or second supervisor.

The sole normative reader, privacy, staging, completion, CLI, operator, and T7
mechanics live in
`specs/007-product-telemetry-blob/contracts/manual-batch-collector.md`. This ADR
records the accepted tool and architecture decision and does not compete with
that contract.

## Binary, build, and Swift-concurrency cost

- **External runtime cost**: the operator machine must already contain Azure CLI
  and GNU coreutils. Both have installed binary/runtime/disk and update cost;
  each collector invocation also pays subprocess plus Azure version/cloud
  preflight cost. Operator maintenance owns those installations and upgrades.
- **Repository and product binary cost**: zero vendored, linked, embedded, or
  packaged bytes in AIDash, its Swift products, or the Python lock. Tests use one
  executable fake `az` rather than installing Azure tooling.
- **Build cost**: no SwiftPM, Xcode project, build phase, CI installation, or
  Python-lock change. Only the existing aidata hook/CI path is exercised.
- **Swift 6 concurrency cost**: none. The seam is a Python subprocess boundary;
  it introduces no Swift import, task, actor, `Sendable`, or isolation surface.

## Alternatives considered

- Python `DefaultAzureCredential` plus repository-owned stdlib LIST/GET was
  rejected because it adds dependency/token handling, pagination, caps,
  checkpoints, and retry state for a one-shot manual outcome.
- Azure Storage SDK was rejected because its repository dependency and API
  surface are unnecessary for one delegated batch.
- Raw `az account get-access-token` parsing was rejected because it exposes token
  output and still leaves service calls to repository code.
- A dedicated service/workload principal was rejected because this version
  deliberately uses the Owner's existing read-only identity and authorizes no
  identity or role change.
- A read/list SAS or the dormant `local-read` policy was rejected because it
  creates another credential/policy path outside the accepted identity boundary.

## Consequences

The earlier `azure-identity` credential and repository-owned LIST/GET plan never
shipped. Direct CLI collection removes that Python dependency, token handling,
pagination, per-object state, and repository-owned retry machinery while
retaining external read-only RBAC and public-repository privacy. It also makes
the pinned external CLI installation an explicit operator prerequisite rather
than pretending it has no machine/runtime cost.
