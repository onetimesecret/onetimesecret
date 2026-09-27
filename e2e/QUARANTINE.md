# E2E Test Quarantine

> Part of the [E2E remediation plan](./docs/e2e-remediation-plan.md) (Phases 1
> & 2.4). **Flake is blocking, not silent**: CI fails on any test that passes
> only on retry (a `flaky` outcome). A flaky test gets fixed, or it gets
> quarantined here — it never rides green on a retry.
>
> This file also tracks **deliberately-dormant** suites (Phase 2.4): tests that
> cannot run in CI yet because they need fixtures or optional deployment config.
> They are turned off honestly (`test.fixme`, or an env gate) and listed below
> so **nobody mistakes a green run for full coverage.**

## How to quarantine a test

1. Mark the test with `test.fixme()` and a one-line reason:

   ```ts
   test.fixme('renders the dashboard chart', async ({ page }) => {
     // fixme: chart hydration races the websocket fixture — see #1234
   });
   ```

   `test.fixme` skips the test and signals "this is known-broken / not-yet-
   runnable" — unlike a bare `test.skip(true, ...)`, which silently reports a
   non-running test as green and is banned by the remediation plan.

2. Open (or link) a GitHub issue describing why it can't run: missing fixture,
   missing config, failure mode + trace/HTML-report links if it's a flake.

3. Add a row to the relevant table below. **Owner and issue link are
   mandatory** — an unowned quarantined test is a deleted test waiting to
   happen.

4. Remove the row (and the `test.fixme` / env gate) in the PR that makes the
   test runnable again.

## Quarantined tests (`test.fixme` — missing fixtures / unimplemented)

These need **seeded data** (a second org, a second member, a captured email)
that does not exist yet; the fixtures are Phase 3 / PR 6 work.

| Test (file › title) | Owner | Issue | Quarantined | Reason |
|---------------------|-------|-------|-------------|--------|
| `full/cross-org-domain-isolation.spec.ts` › whole suite (8 tests) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Needs ≥2 orgs with disjoint custom-domain sets. Was the multi-org failure aborting #3412/#3416 CI (the DOM scraper also needs a rewrite). |
| `full/domains-store-org-cache.spec.ts` › whole suite (5 tests) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Needs ≥2 orgs ("Default Workspace" + "Second Organization") with per-org domain caches to compare. |
| `full/org-switcher-navigation.spec.ts` › whole suite | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | The org switcher only renders for accounts with ≥2 organizations. |
| `full/domain-context-consultant.spec.ts` › 7 custom-domain placeholders | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Unimplemented; each needs a custom domain. The 2 *no-custom-domain* tests in the file still run. |
| `full/domain-sso-config.spec.ts` › TC-DSSO-019 (access denied without entitlement) | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-06-10 | Inverted precondition — asserts the *absence* of `manage_sso`, but the suite is gated on its presence. Needs a no-entitlement lane. |
| `full/invite-flow-states.spec.ts` › INV-002 new user via magic link | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Magic link arrives by email; needs a mail interceptor (Mailpit/MailHog). |
| `full/invite-flow-states.spec.ts` › INV-003 new user via SSO | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs an SSO/IdP configured plus a captured invite email. |
| `full/invite-flow-states.spec.ts` › INV-005 existing user with MFA | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs an MFA-enrolled invitee account (`TEST_MFA_*`). |
| `full/org-invitation-flow.spec.ts` › INV-012 Gmail alias normalization | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs real Gmail accounts + captured invite email. (`normalizeEmail()` is unit-tested.) |
| `full/org-invitation-flow.spec.ts` › INV-017 full invitation acceptance | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-10 | Needs a second account to sign up with the invited email + Mailpit. |
| `full/invite-token-security.spec.ts` › SEC-INV-003 valid invite_token auto-login | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-24 | Needs a seeded invite_token consumed by a fresh signup (second account + mail); CI cannot seed it, so invite-direct-accept never renders. |
| `full/org-invitation-flow.spec.ts` › INV-007b unauthenticated decline | delano | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) | 2026-06-24 | Needs a real pending invitation to decline unauthenticated; CI cannot seed the invitation, so the decline lands on an unexpected URL. |
| `full/organization-settings.spec.ts` › ORG-DETAIL-006 SSO tab opens the SSO panel | delano | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) | 2026-09-26 | Needs org SSO turned on (`ORGS_SSO_ENABLED`) and the `manage_sso` entitlement; no lane configures either. `test.fixme` unless `E2E_SSO_UI` is set. The lane still checks that the SSO tab is absent and that `/sso` redirects to Domains (ORG-DETAIL-001, ORG-DETAIL-011). |

> **Still owed (deferred to a CI-verified follow-up, not in this PR):** the
> org-existence `test.skip(true)` conversions in `scope-switcher`. PR 4 showed
> the org UI does not always render as those tests assert, so converting their
> guards to assertions can introduce fresh red — it must be done against a real
> CI run, not blind. `organization-settings`, `organization-members` and
> `identifier-url-patterns` are converted: their skips came from reading /orgs
> before the list rendered (now `e2e/support/organizations.ts`) and from stale
> selectors, not from missing organizations. Verified locally against the
> full-lane container image.
> The members tests that need other members (roles, removal, hierarchy,
> permissions) sign up a throwaway team through the real invitation flow
> (`e2e/support/members.ts`), so they need no seeded fixture.

## Dormant-in-CI suites (`env`-gated — optional config, **NOT coverage yet**)

These suites assert behaviour that only exists when the target has **optional
deployment config** the CI container does not provision. They are gated on env
flags (`e2e/support/env.ts`) so the skip names a real condition instead of an
unconditional skip — strictly better than `test.skip(true, ...)`, but **still
not coverage** until a lane sets the flag.

> ⚠️ **No CI lane sets any of these flags today**, so every suite below is
> DORMANT in CI: it does not run, cannot fail, and a green run says nothing
> about it. Restoring real coverage is **PR 6's job** — it must add a
> domains/SSO-enabled lane (or local-run docs) that sets these flags and runs
> these suites, alongside the fixtures. Until then, treat these as a *holding
> action* that keeps the gate meaningful for everything else, not as tested.

| Suite | Gate (env var) | Issue |
|-------|----------------|-------|
| `full/domain-config-consistency.spec.ts` | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-email-config.spec.ts` | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-navigation.spec.ts` | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-favicon-refresh.spec.ts` | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-incoming-entitlement.spec.ts` | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-sso-config.spec.ts` | `E2E_CUSTOM_DOMAINS` + `E2E_SSO_UI` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/domain-sso-multi-provider.spec.ts` | `E2E_CUSTOM_DOMAINS` + `E2E_SSO_UI` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `full/identifier-url-patterns.spec.ts` › TC-ID-010, -011, -012, -031, -051 (domain URLs) | `E2E_CUSTOM_DOMAINS` | [#3420](https://github.com/onetimesecret/onetimesecret/issues/3420) |
| `auth/sso-csrf.spec.ts` | `E2E_SSO_UI` | [#2798](https://github.com/onetimesecret/onetimesecret/issues/2798) |
| `full/mfa-bootstrap-reactivity.spec.ts` | `TEST_MFA_*` | [#3421](https://github.com/onetimesecret/onetimesecret/issues/3421) |
