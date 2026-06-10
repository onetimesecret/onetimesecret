# E2E Test Quarantine

> Part of the [E2E remediation plan](./docs/e2e-remediation-plan.md) (Phase 1).
> **Flake is blocking, not silent**: CI fails on any test that passes only on
> retry (a `flaky` outcome). A flaky test gets fixed, or it gets quarantined
> here — it never rides green on a retry.

## How to quarantine a test

1. Mark the test with `test.fixme()` and a one-line reason:

   ```ts
   test.fixme('renders the dashboard chart', async ({ page }) => {
     // fixme: chart hydration races the websocket fixture — see #1234
   });
   ```

   `test.fixme` skips the test *and* fails it if it unexpectedly passes, so a
   silently-recovered test surfaces instead of rotting here.

2. Open (or link) a GitHub issue describing the flake: failure mode, frequency,
   trace/HTML-report artifact links from the failing run.

3. Add a row to the table below. **Owner and issue link are mandatory** — an
   unowned quarantined test is a deleted test waiting to happen.

4. Remove the row (and the `test.fixme`) in the PR that fixes the test.

## Quarantined tests

| Test (file › title) | Owner | Issue | Quarantined | Reason |
|---------------------|-------|-------|-------------|--------|
| `full/organization-members.spec.ts` › MBR-ROLE-001 Owner sees role selector dropdown for non-owner members | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Needs a non-owner member in the test org; multi-member fixture is PR 6 work |
| `full/organization-members.spec.ts` › MBR-ROLE-002 Owner can change member role from member to admin | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Needs a non-owner member in the test org |
| `full/organization-members.spec.ts` › MBR-ROLE-004 Role selector shows only admin and member options | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Needs a non-owner member in the test org |
| `full/organization-members.spec.ts` › MBR-REMOVE-001 Owner sees remove button for non-owner members | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Needs a non-owner member; previous version could not fail (`count >= 0`) |
| `full/organization-members.spec.ts` › MBR-REMOVE-003 Clicking remove shows confirmation dialog | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Needs a removable (non-owner) member |
| `full/organization-members.spec.ts` › MBR-REMOVE-004 Confirming removal removes member from list | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Needs a removable (non-owner) member |
