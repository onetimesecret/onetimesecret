// e2e/support/env.ts

/**
 * Documented environment gates for the E2E suite.
 * (e2e/docs/e2e-remediation-plan.md, Phase 2.4 — defensive-skip triage)
 *
 * Guiding principle 1: **a test must be able to fail.** Runtime
 * probe-then-skip guards ("is the switcher visible? no? skip") report green
 * forever and hide regressions. Where a precondition is genuinely
 * deployment-specific, the decision belongs here instead: a build-time
 * constant derived from an explicit environment variable, named in the
 * `test.skip()` reason, documented in one place. When a gate is enabled the
 * suite *asserts* the feature works — it never probes and silently skips.
 *
 * The CI container (.github/workflows/e2e.yml) sets only `TEST_USER_*`:
 * it runs standalone (billing disabled, so the frontend grants every
 * entitlement — see `useEntitlements.isStandaloneMode`), with
 * `DOMAINS_ENABLED` and `ORGS_SSO_ENABLED` at their `false` defaults and no
 * Stripe catalog. Everything below the credentials block is therefore OFF in
 * CI; enabling a gate against a server that doesn't actually provide the
 * feature produces honest failures, not skips.
 */

// ---------------------------------------------------------------------------
// Account credentials
// ---------------------------------------------------------------------------

/**
 * The primary test account. global.setup.ts registers/signs in this account
 * and the `full`/`full-billing` projects start authenticated as it via
 * storageState. Specs only need the raw credentials to sign in as the same
 * user inside a *fresh* browser context (multi-context invite flows) or
 * after `clearCookies()`.
 */
export const hasTestCredentials = Boolean(
  process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD
);

/** Second account with org-admin role; used by multi-actor member suites. */
export const hasAdminCredentials = Boolean(
  process.env.TEST_ADMIN_EMAIL && process.env.TEST_ADMIN_PASSWORD
);

/** Second account with plain member role; used by multi-actor member suites. */
export const hasMemberCredentials = Boolean(
  process.env.TEST_MEMBER_EMAIL && process.env.TEST_MEMBER_PASSWORD
);

/**
 * Account with an active paid subscription (billing-enabled servers only).
 * Plan-switching flows are meaningless without one.
 */
export const hasSubscriberCredentials = Boolean(
  process.env.TEST_SUBSCRIBER_EMAIL && process.env.TEST_SUBSCRIBER_PASSWORD
);

/**
 * Account with TOTP MFA enrolled, plus either a static `TEST_MFA_OTP` or the
 * `TEST_MFA_SECRET` to generate codes from.
 */
export const hasMfaCredentials = Boolean(
  process.env.TEST_MFA_USER_EMAIL &&
    process.env.TEST_MFA_USER_PASSWORD &&
    (process.env.TEST_MFA_SECRET || process.env.TEST_MFA_OTP)
);

// ---------------------------------------------------------------------------
// Optional server features (explicit opt-in; all OFF in CI)
// ---------------------------------------------------------------------------

/**
 * E2E_SSO_UI=true — the target server runs with OmniAuth configured, so the
 * /signin page renders the SSO button. Gates e2e/auth/sso-csrf.spec.ts.
 */
export const ssoSigninEnabled = process.env.E2E_SSO_UI === 'true';

/**
 * E2E_ORGS_SSO=true — the target server runs with `ORGS_SSO_ENABLED=true`
 * AND the test account's org plan grants `manage_sso` (automatic in
 * standalone mode, plan-gated when billing is enabled). The org-settings SSO
 * tab and /domains/:domain/sso pages exist only behind this dual control.
 */
export const orgsSsoEnabled = process.env.E2E_ORGS_SSO === 'true';

/**
 * E2E_CUSTOM_DOMAINS=<n> — the target server runs with
 * `DOMAINS_ENABLED=true` and the test account's default org owns at least
 * <n> custom domains. There is no domain fixture yet (planned for Phase 3 /
 * PR 6 fixtures.ts), so domain-scoped suites are gated on a pre-provisioned
 * environment.
 */
export const customDomainCount = Number.parseInt(process.env.E2E_CUSTOM_DOMAINS ?? '0', 10) || 0;

/** At least one custom domain provisioned for the test account. */
export const hasCustomDomain = customDomainCount >= 1;

/**
 * E2E_BILLING_UI=true — the target server has a billing catalog (plans with
 * paid CTAs render on /pricing). The `full-billing` project additionally
 * assumes this; the gate exists so the handful of billing-CTA tests outside
 * that project (e2e/auth/) are explicit rather than probe-and-skip.
 */
export const billingUiEnabled = process.env.E2E_BILLING_UI === 'true';

/**
 * ALLOW_DESTRUCTIVE_TESTS=true — opt-in for tests that mutate real billing
 * state (plan changes against Stripe test mode). Never set in CI.
 */
export const allowDestructiveTests = Boolean(process.env.ALLOW_DESTRUCTIVE_TESTS);
