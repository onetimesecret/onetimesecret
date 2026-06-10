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
| `full/org-switcher-navigation.spec.ts` › **all tests** (TC-OSN-001…011) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Every test switches between "Default Workspace" and "A Second Organization" — a hand-provisioned dev account shape; needs the PR 6 second-org fixture |
| `full/scope-switcher.spec.ts` › TC-SS-054 Switching org resets domain scope if domain not available | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Needs second org + per-org domains; had no assertion at all (flagged in #3416 review) |
| `full/cross-org-domain-isolation.spec.ts` › **all tests** (TC-DOI-001…008) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Needs ≥2 orgs with specific domain distributions; was the 8 hard failures aborting #3412/#3416 CI runs (broken DOM-scrape helper times out before its own guard) |
| `full/domains-store-org-cache.spec.ts` › **all tests** (TC-DSC-001…005) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Compares per-org domain caches across two hand-provisioned named orgs |
| `full/domain-context-consultant.spec.ts` › 7 consultant-workflow scenarios | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Declarative `test.skip` placeholders, never implemented; need custom domains on the test account |
| `full/invite-flow-states.spec.ts` › INV-002 new user can join via magic link | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs mail interceptor for magic-link capture |
| `full/invite-flow-states.spec.ts` › INV-003 new user can join via SSO | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs SSO provider + email capture |
| `full/invite-flow-states.spec.ts` › INV-005 existing user with MFA completes invite flow | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs MFA-enrolled invitee account |
| `full/invite-flow-states.spec.ts` › INV-006 signed-in user with matching email can accept directly | delano | [#3419](https://github.com/onetimesecret/onetimesecret/issues/3419) | 2026-06-10 | Self-invite of the storageState user is single-shot; needs a fresh second-account fixture |
| `full/org-invitation-flow.spec.ts` › INV-012 Gmail alias normalization | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs real/intercepted Gmail-alias mailboxes |
| `full/org-invitation-flow.spec.ts` › INV-017 After accepting invitation, user can see the org | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Full acceptance round-trip needs email-verification capture |
