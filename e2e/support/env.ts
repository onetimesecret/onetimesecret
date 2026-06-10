// e2e/support/env.ts
//
// Documented environment gates for the E2E suite
// (e2e/docs/e2e-remediation-plan.md, Phase 2.4: defensive-skip triage).
//
// Guiding principle #1 is "a test must be able to fail": a bare
// `test.skip(true, ...)` can only pass-or-skip, so it gives zero signal. Where
// a test genuinely depends on OPTIONAL deployment configuration that the CI
// container does not provision, gate it on one of the flags below so the skip
// names a real, documented environment condition instead of an unconditional
// skip.
//
// The CI workflow (.github/workflows/e2e.yml) sets NONE of these, so gated
// suites skip there cleanly (no false-green "passes"); set them locally
// against a suitably-configured target to exercise the suite.
//
// Note the deliberate split:
//   - OPTIONAL CONFIG (a custom domain exists, SSO UI is on, an MFA account
//     exists) -> env-gated here. It is deployment configuration.
//   - SEEDED DATA RELATIONSHIPS (a second organization, a second member, a
//     captured invite email) -> NOT env-gated. Those need fixtures, so the
//     suites are `test.fixme`'d and tracked in e2e/QUARANTINE.md
//     (issues #3419 / #3420 / #3421). The fixture work is Phase 3 / PR 6.

/** True when an env var is present and not an explicit falsey string. */
function flag(name: string): boolean {
  const v = process.env[name];
  return v !== undefined && v !== '' && v !== '0' && v.toLowerCase() !== 'false';
}

/**
 * Custom domains available on the target account. Set E2E_CUSTOM_DOMAINS to a
 * comma-separated list (or any truthy value) when the target runs with custom
 * domains enabled and at least one provisioned. Suites that navigate
 * `/org/:id/domains/:extid/...` gate on `hasCustomDomains`.
 */
export const customDomains: string[] = (process.env.E2E_CUSTOM_DOMAINS ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

export const env = {
  /** ≥1 custom domain is provisioned on the test account (E2E_CUSTOM_DOMAINS). */
  hasCustomDomains: customDomains.length > 0,
  customDomains,

  /** The SSO sign-in UI is configured (E2E_SSO_UI) — OmniAuth/SSO buttons render. */
  hasSsoUi: flag('E2E_SSO_UI'),

  /** An MFA/TOTP-enrolled account is available (TEST_MFA_USER_*). */
  hasMfaAccount:
    flag('TEST_MFA_USER_EMAIL') &&
    flag('TEST_MFA_USER_PASSWORD') &&
    flag('TEST_MFA_USER_SECRET'),
};

/**
 * Reason strings for the gates above. Keeping them here means a skip's message
 * always points at the exact env var to set, instead of a vague "feature not
 * available".
 */
export const gateReason = {
  customDomains:
    'Requires a custom domain on the test account — set E2E_CUSTOM_DOMAINS ' +
    '(target must run with domains enabled). See issue #3420.',
  ssoUi:
    'Requires the SSO sign-in UI configured — set E2E_SSO_UI (target must have ' +
    'an OmniAuth/SSO provider enabled).',
  mfaAccount:
    'Requires an MFA/TOTP-enrolled account — set TEST_MFA_USER_EMAIL / ' +
    'TEST_MFA_USER_PASSWORD / TEST_MFA_USER_SECRET.',
} as const;
