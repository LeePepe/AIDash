# TestFlight delivery handoff

`.github/workflows/testflight.yml` publishes app-relevant commits after they are
merged to protected `main`. A manual dispatch remains available for authorized
releases and recovery from a missing initial marker.

The workflow uses the existing `fastlane ios beta` lane. Before the first real
upload, configure the five repository secrets and the Apple account resources
below.

The single release job has `contents: write` permission so it can move the
public release marker after upload. Checkout credentials are not persisted, and
the job token is exposed only to that marker compare-and-swap step.

## GitHub secrets

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID |
| `ASC_KEY_P8_BASE64` | Base64-encoded `.p8` private key |
| `ASC_TEAM_ID` | Apple Developer Team ID |
| `KEYCHAIN_PASSWORD` | Login password for the self-hosted runner account |

Create an App Store Connect API key with the App Manager role, download its
`.p8` file, and configure the secrets:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | gh secret set ASC_KEY_P8_BASE64
gh secret set ASC_KEY_ID
gh secret set ASC_ISSUER_ID
gh secret set ASC_TEAM_ID
gh secret set KEYCHAIN_PASSWORD
```

The public repository must not contain the Apple Developer Team ID. CI passes
`ASC_TEAM_ID` to `fastlane/identity.rb` as `AIDASH_DEVELOPMENT_TEAM`; local
development continues to use the ignored `Configs/Identity.local.xcconfig`.

## Apple account prerequisites

1. Create the App ID for `com.tianpli.aidash`, enable iCloud, and associate
   `iCloud.com.tianpli.aidash`.
2. Install an Apple Distribution certificate and its private key in the
   self-hosted runner account's login keychain. Its ACL must already permit
   non-interactive codesigning.
3. Create the App Store Connect app and an internal TestFlight group named
   `Internal`.

The lane refreshes the provisioning profile at runtime. It allocates the next
build number across all marketing versions and uses `MARKETING_VERSION` from
`project.yml`. Internal-group distribution remains lane-owned and best-effort.

## Release behavior

### Automatic post-merge release

A push to `main` starts the workflow after merge. The candidate is exactly
`github.sha`; the workflow never substitutes a newer branch tip. The candidate
must be reachable from the fetched official `main` branch.

The lightweight `testflight/last-released` tag is the only durable release
state:

- If the marker equals the candidate, the run skips, even when forced.
- If the marker is an ancestor, the workflow checks the accumulated
  `marker..candidate` paths.
- A missing marker or non-ancestor relationship fails closed.
- App changes under `Apps/AIDashApp/`, `Packages/AIDashCore/`,
  `Packages/AIDashUI/`, `Packages/DesignKit/`, `Configs/`, `project.yml`, or
  `fastlane/` are release-relevant.
- Docs, specs, workflows, scripts, CLI, and aidata-only changes do not release.

### Manual release

Actions -> testflight -> Run workflow pins the current official `main` SHA
once. `force=true` bypasses only path relevance. It does not bypass candidate
validation, marker equality, signing, upload, or marker safety. Manual force is
also the only authorized way to bootstrap a missing marker:

```bash
gh workflow run testflight.yml --ref main -f force=true
```

### Signing and cleanup

The workflow unlocks `login.keychain-db` immediately before release and always
attempts to re-lock it. It does not change keychain settings, search lists, or
partition lists; those are runner provisioning responsibilities.

The lane generates and installs a fresh provisioning profile. The workflow
directs its downloaded profile into a run-specific directory, reads that
profile's UUID, and removes only the matching installed profile during
`always()` cleanup, preserving pre-existing runner state.

After a successful upload, the workflow updates `testflight/last-released` with
a compare-and-swap lease against the exact marker observed during eligibility.
Skipped or pre-upload failed runs never move the marker. Upload and marker
movement are not atomic: if upload succeeds but the lease is rejected, a later
run may upload another build. There is no automatic retry, rollback, queue,
journal, cursor, or recovery ref.

Successful marker compare-and-swap is the release-success boundary. The final
`always()` cleanup removes local workflow state, re-locks the keychain, and
writes a secret-free run summary. Cleanup failures after that boundary emit
warnings only and cannot reclassify the successful release.

## Verification and troubleshooting

The summary records the candidate, marker state, relevance decision, marker
CAS result, final outcome, cleanup status, and workflow URL. A real TestFlight
upload is not a PR gate; the first eligible post-merge run provides delivery
evidence.

The prior tracked manual-only regression was removed because post-merge
automatic release supersedes that behavior. The unpublished revision-3
shadow-policy suite was intentionally discarded rather than ported. Replacement
coverage is limited to the exact production relevance classifier, stable
workflow structure, and complete-workflow lint required by Spec 007.

| Symptom | Cause / action |
|---|---|
| Missing API key or Team ID | Configure the named repository secret |
| `errSecInternalComponent` | Verify the runner keychain is unlocked and its certificate ACL is preconfigured |
| iCloud capability mismatch | Update the App ID/container and regenerate the profile |
| Build uploaded but testers cannot see it | Verify the internal group name or `TESTFLIGHT_GROUPS` |
| Bundle version is not higher | A prior upload may have completed before marker CAS; rerun after diagnosis |
| Marker missing | Use an authorized manual `force=true` bootstrap |
| Marker is not an ancestor | Investigate the tag; do not overwrite it manually |
| Workflow remains queued | Restore the `aidash-mac` runner |
