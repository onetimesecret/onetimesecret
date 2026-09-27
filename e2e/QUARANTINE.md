# E2E Test Quarantine

> Part of the [E2E remediation plan](./docs/e2e-remediation-plan.md).
> Container E2E (`.github/workflows/e2e.yml`) runs two **blocking** lanes, each
> with its own image build, Valkey and flaky gate:
>
> | Lane | Auth mode | Suite |
> |------|-----------|-------|
> | `container-e2e-tests (simple)` | simple | `e2e/all/` |
> | `container-e2e-tests (full)` | full | `e2e/full/` (plus the `setup` project) |
>
> **Flake is blocking, not silent**: a lane fails on any test that passes only
> on retry (a `flaky` outcome). A flaky test gets fixed, or it gets
> quarantined here; it never rides green on a retry.
>
> This file also lists every test that is turned off on purpose because it
> needs a fixture or deployment config the lanes do not provide. They are
> turned off honestly (`test.fixme`, or an env gate) and listed below so
> **nobody mistakes a green run for full coverage.** Every `test.fixme` and
> every env-gated skip in `e2e/full/` has a row here.

## How to quarantine a test

1. Mark the test with `test.fixme()` and a one-line reason:

   ```ts
   test.fixme('renders the dashboard chart', async ({ page }) => {
     // fixme: chart hydration races the websocket fixture — see #1234
   });
   ```

   `test.fixme` skips the test and signals "this is known-broken / not-yet-
   runnable" — unlike a bare `test.skip(true, ...)` or a skip on a DOM probe,
   which silently reports a non-running test as green and is banned by the
   remediation plan. A `test.fixme` may be conditional only on a documented
   env flag (`e2e/support/env.ts`).

2. Open (or link) a GitHub issue describing why it can't run: missing fixture,
   missing config, failure mode + trace/HTML-report links if it's a flake.

3. Add a row to the relevant table below. **Owner and issue link are
   mandatory** — an unowned quarantined test is a deleted test waiting to
   happen.

4. Remove the row (and the `test.fixme` / env gate) in the PR that makes the
   test runnable again.

## Quarantined tests (`test.fixme` — missing fixtures / unimplemented)

These need data or config the full lane does not provide: a custom domain,
org SSO or an SSO identity provider, magic-link sign-in with a mail
interceptor, an MFA-enrolled account, an account without `manage_sso`, or an
account with two organizations **and** custom domains. Tests that only need
more accounts or a second organization build them with throwaway accounts
instead (`e2e/support/members.ts`, `e2e/support/workspaces.ts`). Tests that
need a pending invitation send one and read its token through the owner's
invitations API; no mail is involved.

| Test (file › title) | Owner | Issue | Quarantined | Reason |
|---------------------|-------|-------|-------------|--------|
| `full/cross-org-domain-isolation.spec.ts` › whole suite (8 tests) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Needs ≥2 orgs with disjoint custom-domain sets. Was the multi-org failure aborting #3412/#3416 CI (the DOM scraper also needs a rewrite). |
| `full/domains-store-org-cache.spec.ts` › whole suite (5 tests) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Needs ≥2 orgs ("Default Workspace" + "Second Organization") with per-org domain caches to compare. |
| `full/scope-switcher.spec.ts` › TC-SS-009 (org switcher on domain detail), TC-SS-054 (workspace switch resets domain scope) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-09-26 | Need an account with two workspaces and custom domains. The lane's two-workspace owner has no custom domain, and the storageState account owns one solo workspace. |
| `full/domain-context-consultant.spec.ts` › 7 custom-domain placeholders | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Unimplemented; each needs a custom domain. The 2 *no-custom-domain* tests in the file still run. |
| `full/domain-sso-config.spec.ts` › TC-DSSO-019 (access denied without entitlement) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Inverted precondition — asserts the *absence* of `manage_sso`, but the suite is gated on its presence. Needs a no-entitlement lane. |
| `full/invite-flow-states.spec.ts` › INV-002 new user via magic link | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Magic links are off unless `AUTH_EMAIL_AUTH_ENABLED=true` (`email_auth` in `etc/defaults/auth.defaults.yaml`), and the link arrives by email, so this also needs a mail interceptor (Mailpit). The invite page's own forms offer a magic link only on a custom domain (`show_invite.rb` sends `auth_methods` only there); on the canonical host the invitee reaches it through `/signin` only when sign-in is restricted to email auth. |
| `full/invite-flow-states.spec.ts` › INV-003 new user via SSO | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs an SSO identity provider. The invite page's own forms offer SSO only on a custom domain with SSO available (`show_invite.rb`); on the canonical host the invitee reaches it through `/signin` only when sign-in is restricted to SSO. The invitation token comes from the invitations API, as in the other invite tests. |
| `full/invite-flow-states.spec.ts` › INV-005 existing user with MFA | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs an MFA-enrolled invitee account (`TEST_MFA_*`). |
| `full/organization-settings.spec.ts` › ORG-DETAIL-006 SSO tab opens the SSO panel | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-09-26 | Needs org SSO turned on (`ORGS_SSO_ENABLED`) and the `manage_sso` entitlement; no lane configures either. `test.fixme` unless `E2E_SSO_UI` is set. The lane still checks that the SSO tab is absent and that `/sso` redirects to Domains (ORG-DETAIL-001, ORG-DETAIL-011). |

## Dormant-in-CI suites (`env`-gated — optional config, **NOT coverage yet**)

These suites assert behaviour that only exists when the target has **optional
deployment config** the lanes do not provision: custom domains, org SSO, an
MFA-enrolled account. They are gated on env flags (`e2e/support/env.ts`), so
the skip names a real condition instead of an unconditional skip. Inside the
gates, missing data fails the test: a gated suite that runs on a target
without the fixture it needs reports failures, not skips.

> ⚠️ **No CI lane sets any of these flags today**, so every suite below is
> DORMANT in CI: it does not run, cannot fail, and a green run says nothing
> about it. Treat these as a *holding action*, not as tested. No lane has run
> them since they were gated (PR 5), and their runtime skips were turned into
> assertions on 2026-09-27 with only lint and a type check to verify them, so
> expect fixes the first time one runs against a configured target.

| Suite | Tests | Gate (env var) | Issue |
|-------|-------|----------------|-------|
| `full/domain-config-consistency.spec.ts` | 11 | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-email-config.spec.ts` | 17 | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-navigation.spec.ts` | 5 | `E2E_CUSTOM_DOMAINS`; TC-DN-001 and -005 (SSO page) are also `test.fixme` without `E2E_SSO_UI` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-favicon-refresh.spec.ts` | 4 | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-incoming-entitlement.spec.ts` | 13 | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-sso-config.spec.ts` | 19 | `E2E_CUSTOM_DOMAINS` + `E2E_SSO_UI`; the case that needs two domains is `test.fixme` unless `E2E_CUSTOM_DOMAINS` lists two. TC-DSSO-019 is the 20th test in the file and is `test.fixme` (row above) | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-sso-multi-provider.spec.ts` | 13 | `E2E_CUSTOM_DOMAINS` + `E2E_SSO_UI`; the five cases that need two domains are `test.fixme` unless `E2E_CUSTOM_DOMAINS` lists two | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/identifier-url-patterns.spec.ts` › TC-ID-010, -011, -012, -031, -051 (domain URLs) | 5 | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/scope-switcher.spec.ts` › domain switcher with custom domains | 12 | `test.fixme` unless `E2E_CUSTOM_DOMAINS` (must list the domain names; the first is used) | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/mfa-bootstrap-reactivity.spec.ts` | 10 | `TEST_MFA_*`; TC-MFA-004 also needs `TEST_MFA_SECRET` | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) |
| `auth/sso-csrf.spec.ts` (not in either container lane) | 8 | `E2E_SSO_UI` | [#2798](https://github.com/onetimesecret/onetimesecret/issues/2798) |
