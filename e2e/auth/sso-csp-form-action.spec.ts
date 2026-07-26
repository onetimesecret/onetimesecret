// e2e/auth/sso-csp-form-action.spec.ts
//
// E2E regression coverage for GitHub issue #3848 (SSO CSP form-action).
//
// Background: otto 2.5+ emits `Content-Security-Policy: ... form-action 'self'`.
// The SSO sign-in is a real <form> POST to /auth/sso/:provider, which the server
// answers with a 302 redirect to the identity provider (a cross-origin URL).
// Chromium enforces the form-action directive across the *entire* redirect chain,
// so `form-action 'self'` blocks that redirect and fires a
// `securitypolicyviolation` event with effectiveDirective 'form-action' — the SSO
// flow dies before it reaches the IdP. (Firefox/WebKit do not enforce form-action
// across redirects, so the bug was Chromium-only.)
//
// The fix appends the active SSO IdP origin(s) to the form-action directive
// (Onetime.auth_config.sso_form_action_origins, overridable via
// SSO_FORM_ACTION_ORIGINS), so the redirect is permitted.
//
// HOLDING ACTION — committed-but-dormant coverage. Like the sibling
// sso-csrf.spec.ts, these assert the SSO sign-in UI, which only renders when an
// OmniAuth/SSO provider is configured — optional deployment config the CI
// container does not set. Env-gated on E2E_SSO_UI so the skip names a real
// condition; CI does not set it (and does not run e2e/auth/ at all), so this
// suite is DORMANT until a SSO-configured target/lane exists. It only exercises
// real CSP enforcement when pointed at a SSO-configured target with E2E_SSO_UI
// set (and run under Chromium: `pnpm test:playwright --project=chromium`).
//
// CRITICAL DIFFERENCE from sso-csrf.spec.ts: that suite STUBS
// HTMLFormElement.prototype.submit to keep the page from navigating away. This
// suite must NOT stub submit — the whole point is to let the real form POST and
// its 302 redirect run so Chromium can (or cannot) enforce form-action across the
// redirect chain. Instead we install a `securitypolicyviolation` listener via
// addInitScript and assert no form-action violation is recorded.

import { test, expect } from '@playwright/test';

import { env, gateReason } from '../support/env';

// See sso-csrf.spec.ts for the full rationale — DORMANT until a SSO-configured
// target/lane sets E2E_SSO_UI.
test.beforeEach(() => {
  test.skip(!env.hasSsoUi, gateReason.ssoUi);
});

/**
 * Shape recorded for each captured form-action CSP violation. Kept in sync
 * between the in-page recorder (addInitScript) and the reader (page.evaluate).
 */
type FormActionCspViolation = {
  effectiveDirective: string;
  violatedDirective: string;
  blockedURI: string;
  documentURI: string;
};

test.describe('SSO CSP form-action (#3848)', () => {
  test.beforeEach(async ({ page }) => {
    // Extended timeout for page load (mirrors sso-csrf.spec.ts).
    page.setDefaultTimeout(15000);
  });

  test('SSO form POST -> IdP redirect is not blocked by CSP form-action', async ({
    page,
  }) => {
    // Install the violation recorder BEFORE any document loads, so it survives
    // the reload below and is present on the signin document that owns the form.
    // The event fires on the initiating (OTS) document when the redirect is
    // blocked — which also means the page stays on the OTS origin, so the
    // recorded array is still readable afterwards. When the redirect is allowed
    // the page navigates to the IdP and the array is simply empty (no violation).
    await page.addInitScript(() => {
      const w = window as unknown as {
        __formActionCspViolations?: FormActionCspViolation[];
      };
      const records = w.__formActionCspViolations ?? [];
      w.__formActionCspViolations = records;

      document.addEventListener('securitypolicyviolation', (event) => {
        const directive = event.effectiveDirective || event.violatedDirective || '';
        if (directive.includes('form-action')) {
          records.push({
            effectiveDirective: event.effectiveDirective,
            violatedDirective: event.violatedDirective,
            blockedURI: event.blockedURI,
            documentURI: event.documentURI,
          });
        }
      });
    });

    await page.goto('/signin');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const ssoButton = page.locator('[data-testid="sso-button"]');
    // Gated on E2E_SSO_UI above, so the SSO button must render here.
    await expect(ssoButton).toBeVisible();

    const otsOrigin = new URL(page.url()).origin;

    // Real click — NO submit stub. This triggers submitSsoLogin(), which builds
    // and submits a POST form to /auth/sso/:provider and lets the browser follow
    // the server's 302 to the IdP.
    await ssoButton.click();

    // Wait for the redirect chain to resolve one way or the other:
    //  - fix present  -> the browser follows the 302 off the OTS origin (resolves)
    //  - regression    -> Chromium blocks the redirect, we stay on the OTS origin
    //                     and this times out (caught) so we inspect the recorder.
    // No waitForTimeout / networkidle (both banned by eslint) — this is a
    // URL-level web-first wait.
    await page
      .waitForURL((url) => url.origin !== otsOrigin, { timeout: 10000 })
      .catch(() => undefined);

    const violations = await page.evaluate(() => {
      const w = window as unknown as {
        __formActionCspViolations?: FormActionCspViolation[];
      };
      return w.__formActionCspViolations ?? [];
    });

    const finalUrl = page.url();
    const leftOtsOrigin = new URL(finalUrl).origin !== otsOrigin;

    // Authoritative regression assertion (#3848): Chromium must NOT report a
    // form-action CSP violation for the SSO form POST -> IdP 302 redirect.
    expect(
      violations,
      'Chromium reported a form-action CSP violation: the SSO form POST -> IdP ' +
        '302 redirect was blocked. The active IdP origin is missing from the CSP ' +
        'form-action directive (regression of #3848). Recorded violations: ' +
        JSON.stringify(violations)
    ).toEqual([]);

    // Corroborating signal: with the IdP origin allowed, the browser actually
    // leaves the OTS origin for the provider.
    expect(
      leftOtsOrigin,
      `Expected the SSO form POST to redirect off the OTS origin (${otsOrigin}) ` +
        `to the IdP; still at ${finalUrl}.`
    ).toBe(true);
  });

  test('CSP form-action directive advertises an IdP origin beyond \'self\'', async ({
    page,
  }) => {
    // Non-navigational corroboration of the same fix at the header level.
    // Pre-fix the directive was exactly `form-action 'self'`; the #3848 fix
    // appends the active SSO IdP origin(s), so it must carry at least one
    // scheme-qualified origin in addition to the 'self' keyword.
    const response = await page.request.get('/signin');
    const csp = response.headers()['content-security-policy'] ?? '';

    const match = csp.match(/form-action ([^;]+)/i);
    expect(match, `No form-action directive in CSP header: "${csp}"`).not.toBeNull();

    const sources = (match?.[1] ?? '').trim().split(/\s+/);
    const hasOrigin = sources.some((source) => /^https?:\/\//i.test(source));
    expect(
      hasOrigin,
      `CSP form-action is "${sources.join(' ')}" — expected an IdP origin ` +
        "beyond 'self' (regression of #3848; set SSO_FORM_ACTION_ORIGINS if the " +
        'IdP origin is not auto-derived).'
    ).toBe(true);
  });
});
