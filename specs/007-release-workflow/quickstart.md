# Quickstart: Verify the Minimal Release Workflow

## Final diff scope

The implementation PR may change only:

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py   # delete
scripts/ci/tests/test_testflight_relevance.py     # add
docs/testflight-handoff.md
```

The unpublished shadow suite `scripts/ci/tests/test_testflight_release.py` must
not exist in the final tree or PR diff. Its discard must be stated in the PR
body. Planning artifacts remain byte-identical during implementation.

## Focused evidence

1. Confirm every final path resolves to `RepoInfra`.
2. Run the production classifier unit tests:

   ```text
   /usr/bin/python3 -m pytest scripts/ci/tests/test_testflight_relevance.py -q
   ```

   Required cases: every allowed root, representative excluded roots, mixed
   input, empty input, exact `project.yml`, and root-prefix near misses.

3. Install actionlint locally if absent, record `actionlint -version`, and run:

   ```text
   actionlint .github/workflows/testflight.yml
   ```

   Planning-time Homebrew reports stable 1.7.12. Installation or lint failure
   blocks delivery; pytest is not a substitute for workflow lint.

4. Stage only the declared paths and let repository hooks run the normal
   RepoInfra gate. Confirm context audit, task freshness, `git diff --check`, and
   exact path manifest.
5. Inspect the workflow to prove:
   - exact automatic `head_sha`, full history, and tag fetch;
   - successful same-repository `build` push on `main` guard;
   - one self-hosted job/group and `cancel-in-progress: false`;
   - irrelevant summary occurs before any secret-bearing step;
   - all five secrets appear only on build/upload;
   - marker movement follows successful lane completion;
   - `always()` cleanup restores keychain state and removes local temp artifacts;
   - no retry, CAS-only job, cursor, journal, recovery ref, or shadow suite.
6. Freeze the candidate and obtain AI Reviewer PASS before publication.

Do not run Xcode tests, host-based app tests, or a real TestFlight upload.

## Delivery gates

- Team Lead must preserve and not publish `e8c353ce`, and establish the revised
  implementation line under the delivery-workspace recovery contract.
- Protected workflow changes require Owner approval.
- MY-1692 remains the merge/ship gate.
- If revised implementation review round 2 fails, park and report to the Owner
  delegate; do not request a third round or Owner escalation.
