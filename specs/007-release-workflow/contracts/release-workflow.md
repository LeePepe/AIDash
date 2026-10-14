# Contract: TestFlight Release Workflow

## Entrypoints

### Automatic

- Event: `workflow_run`
- Workflow name: `build`
- Type: `completed`
- Branch: `main`
- Required conclusion: `success`
- Candidate: exact `workflow_run.head_sha`

### Manual

- Event: `workflow_dispatch`
- Input: `force` boolean, default false
- Candidate: `main` resolved once at run start
- `force=true` bypasses only app-path relevance

## App-relevant path allowlist

```text
Apps/AIDashApp/**
Packages/AIDashCore/**
Packages/AIDashUI/**
Packages/DesignKit/**
Configs/**
project.yml
fastlane/**
```

Every other path is non-triggering unless manual force is true.

## Absolute pre-upload invariants

1. Candidate resolves to a commit.
2. Automatic candidate comes from successful `build` on `main`.
3. Existing marker dereferences to a commit and is an ancestor of candidate.
4. Candidate differs from marker.
5. Version/label evidence is valid and unambiguous.
6. Required existing secrets are present.

No input, including manual force, bypasses these invariants.

## Marker metadata

Successful releases replace `testflight/last-released` with an annotated tag:

```text
marketing-version=<effective semantic version>
```

The tag target is the exact uploaded candidate. Unknown, duplicate, or invalid
metadata fields are rejected. A legacy lightweight tag is valid but supplies no
version metadata.

## Summary contract

Every terminal path writes a secret-free summary containing:

- event kind and candidate SHA;
- marker state/commit when available;
- terminal outcome and reason;
- effective marketing version when selected;
- build number and GitHub run URL on success.

## Failure contract

- No automatic retry or rollback.
- No alternate runner, credential, signing, or upload path.
- Internal-group distribution failure is fatal.
- Marker update failure is fatal even after upload.
- Stale/non-ancestral candidates never move the marker backward.
