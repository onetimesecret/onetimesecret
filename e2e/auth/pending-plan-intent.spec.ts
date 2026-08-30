// e2e/auth/pending-plan-intent.spec.ts
//
// E2E for the pending plan intent flow: a plan chosen BEFORE signup must
// still be the plan on offer AFTER the user verifies their email and signs
// in (issues #3126, #4306).
//
// ─────────────────────────────────────────────────────────────────────────────
// THE JOURNEY, AND WHY IT NEEDS A BROWSER
// ─────────────────────────────────────────────────────────────────────────────
//
//   /signup?product=identity_plus_v1&interval=monthly   (or via a pricing CTA)
//     → submit → /check-email
//     → verification email (real SMTP → Mailpit)
//     → open the link IN A FRESH BROWSER CONTEXT
//     → /signin?redirect=/billing/plans?product=identity_plus_v1&interval=monthly
//     → sign in → /billing/:extid/plans?product=identity_plus_v1&interval=monthly
//
// Server-side, the intent rides as pending_plan_intent on the Customer
// (24h TTL): captured at create-account, validated and surfaced as
// json_response[:redirect] at verify-account (apps/web/auth/config/hooks/
// account.rb), and consumed into `billing_redirect` on the login response
// (hooks/billing.rb). The fresh browser context is what makes this a real
// test: verification links get opened from mail clients, so nothing from
// the signup tab (history state, sessionStorage, session cookie) may be
// load-bearing.
//
// This file also keeps the lighter query-preservation tests from #3126 —
// the SPA-side plumbing (pricing CTA → signup URL, signin link, the POST
// bodies) that the full journey builds on. They run against any target;
// the journey tests additionally need the email environment below.
//
// ─────────────────────────────────────────────────────────────────────────────
// PROJECT / ENVIRONMENT (journey tests)
// ─────────────────────────────────────────────────────────────────────────────
//
// Runs in the `chromium` project (e2e/all + e2e/auth): no `setup` dependency
// and no storageState — every context this spec touches must start
// unauthenticated, including the first one.
//
// On top of the email environment documented in e2e/support/auth-journey.ts
// (full auth mode, AUTH_AUTOVERIFY=false, SMTP → Mailpit, a running job
// worker, signup rate limit off), the journey needs:
//   BILLING_ENABLED=true            and a catalog that resolves
//                                   identity_plus_v1 (etc/billing.yaml or
//                                   materialized plans) — otherwise
//                                   verify-account validates the intent,
//                                   fails, and correctly drops the redirect
//
//   pnpm test:playwright e2e/auth/pending-plan-intent.spec.ts \
//     --project=chromium
//   # with PLAYWRIGHT_BASE_URL=https://dev.onetime.dev
//   #      MAILPIT_URL=https://dev.onetime.dev:8025
//
// Mailpit reachability is asserted in the journey describe's beforeAll
// rather than skipped on: a silent skip would turn "the feature is broken"
// into a green run.

import { expect, test, type Page } from '@playwright/test';

import {
  signIn,
  submitSignup,
  verifyInFreshContext,
  waitForAppReady,
  waitForPathname,
} from '../support/auth-journey';
import { MAILPIT_URL, isMailpitReachable, uniqueEmailAddress } from '../support/mailpit';

/**
 * Per-spec signup identity, threaded into the shared journey helpers. The
 * password satisfies the strict password_requirements ruleset so the spec
 * behaves identically on a target that leaves
 * AUTH_PASSWORD_REQUIREMENTS_ENABLED at its default (on).
 */
const SIGNUP_OPTIONS = { emailPrefix: 'plan-4306', password: 'E2ePlanIntent!4306pw' };

/** The plan the journey selects. Must exist in the target's billing catalog. */
const PLAN = { product: 'identity_plus_v1', interval: 'monthly' } as const;

/**
 * The sign-in destination verify-account must mint for a VALID plan intent:
 * the SPA's plans route with the selection in the query. (The historical
 * three-segment /billing/plans/:product/:interval shape matches no route —
 * see the hook comment in apps/web/auth/config/hooks/account.rb.)
 */
const EXPECTED_SIGNIN_REDIRECT = `/billing/plans?product=${PLAN.product}&interval=${PLAN.interval}`;

/**
 * Starts recording the JSON body of the next POST whose URL contains
 * `urlFragment`, and returns a getter for it.
 *
 * An observer, NOT a page.route() handler: a route handler puts the test in
 * the request path and lets it rewrite the body, which is exactly what these
 * tests must not do — the point is to record what the product sends. Reading
 * off the event stream cannot lie.
 */
function observePostBody(
  page: Page,
  urlFragment: string
): () => Record<string, unknown> | null {
  let body: Record<string, unknown> | null = null;
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().includes(urlFragment)) {
      body = request.postDataJSON() ?? null;
    }
  });
  return () => body;
}

/**
 * Fills whichever password sign-in surface the target renders (plain
 * SignInForm vs the tabbed PasswordlessFirstSignIn) WITHOUT submitting.
 * The request-capture test below wants the form on screen, filled, so it
 * can observe the login POST — not a completed login.
 */
async function fillSignInForm(page: Page, email: string, password: string): Promise<void> {
  const signinForm = page.getByTestId('signin-form');
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await expect(signinForm.or(passwordTab).first()).toBeVisible();

  if (await passwordTab.isVisible()) {
    await passwordTab.click();
    await page.getByTestId('password-email-input').fill(email);
    await page.getByTestId('password-input').fill(password);
  } else {
    await page.getByTestId('signin-email-input').fill(email);
    await page.getByTestId('signin-password-input').fill(password);
  }
}

/** Submits whichever sign-in surface fillSignInForm just filled. */
async function submitSignInForm(page: Page): Promise<void> {
  const passwordSubmit = page.getByTestId('password-submit');
  const plainSubmit = page.getByTestId('signin-submit');
  if (await passwordSubmit.isVisible()) {
    await passwordSubmit.click();
  } else {
    await plainSubmit.click();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Query preservation (#3126): the SPA-side plumbing the journey rides on
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Pending Plan Intent - Signup Flow', () => {
  test('pricing deep link preserves product and interval in signup redirect', async ({
    page,
  }) => {
    // Visit pricing page with specific plan
    await page.goto(`/pricing/${PLAN.product}/yearly`);
    await waitForAppReady(page);

    // The CTA for the deep-linked plan, located by the BEHAVIOUR under test:
    // Pricing.vue's getSignupUrl puts the plan id in the CTA href
    // (/signup?product=<id>&interval=…). Located by href rather than by
    // highlight-ring classes or "the first Get started link" — the highlight
    // class is styling, and the first CTA on the page can be another tier's
    // (the free plan's links to /signup with NO product at all), which is
    // exactly the wrong-CTA flake repeat-runs surfaced here.
    const planCta = page.locator(`a[href*="product=${PLAN.product}"]`).first();

    // Plan cards render after the plans fetch, later than app-ready — so
    // WAIT for the CTA, and only skip if it genuinely never appears
    // (billing disabled on the target). An isVisible() snapshot here skips
    // falsely whenever the check races the fetch.
    const ctaAppeared = await planCta
      .waitFor({ state: 'visible', timeout: 10_000 })
      .then(() => true, () => false);
    test.skip(!ctaAppeared, 'No plan CTAs available - billing may be disabled');

    await planCta.click();

    // Verify redirect to signup with query params
    await expect(page).toHaveURL(/\/signup\?/);
    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe(PLAN.product);
    expect(url.searchParams.get('interval')).toBe('yearly');
  });

  test('signup form displays with preserved query params', async ({ page }) => {
    // Navigate directly to signup with billing params
    await page.goto(`/signup?product=${PLAN.product}&interval=yearly`);
    await waitForAppReady(page);

    // Verify signup form is displayed
    const signupForm = page.getByTestId('signup-form');
    await expect(signupForm).toBeVisible();

    // Form fields should be accessible
    await expect(page.getByTestId('signup-email-input')).toBeVisible();
    await expect(page.getByTestId('signup-password-input')).toBeVisible();
    await expect(page.getByTestId('signup-terms-checkbox')).toBeVisible();
    await expect(page.getByTestId('signup-submit')).toBeVisible();
  });

  test('signin link preserves billing params', async ({ page }) => {
    // Navigate to signup with billing params
    await page.goto(`/signup?product=${PLAN.product}&interval=yearly`);
    await waitForAppReady(page);

    // Find the "Sign in" link in the footer
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await expect(signinLink).toBeVisible();

    // Click and verify params are preserved
    await signinLink.click();
    await expect(page).toHaveURL(/\/signin\?/);

    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe(PLAN.product);
    expect(url.searchParams.get('interval')).toBe('yearly');
  });

  test('signup form submission includes billing params', async ({ page }) => {
    const getRequestBody = observePostBody(page, '/auth/create-account');

    await page.goto(`/signup?product=${PLAN.product}&interval=yearly`);
    await waitForAppReady(page);

    // Fill form with test data. A unique address, because this really does
    // create an account on the target.
    await page.getByTestId('signup-email-input').fill(uniqueEmailAddress('plan-3126-body'));
    await page.getByTestId('signup-password-input').fill(SIGNUP_OPTIONS.password);
    await page.getByTestId('signup-terms-checkbox').check();

    // Submit and wait for the response (pass or fail — only the request
    // body is under test here; the full journey test below owns the rest)
    await Promise.all([
      page.waitForResponse((response) => response.url().includes('/auth/create-account')),
      page.getByTestId('signup-submit').click(),
    ]);

    // Verify billing params were included in request
    const requestBody = getRequestBody();
    expect(requestBody, 'the SPA sent no body to /auth/create-account').not.toBeNull();
    expect(requestBody?.product).toBe(PLAN.product);
    expect(requestBody?.interval).toBe('yearly');
  });
});

test.describe('Pending Plan Intent - Query Param Validation', () => {
  test('monthly interval is preserved through signup flow', async ({ page }) => {
    await page.goto('/signup?product=team_plus_v1&interval=monthly');
    await waitForAppReady(page);

    // Click signin link to verify param preservation
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await signinLink.click();
    await expect(page).toHaveURL(/\/signin\?/);

    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe('team_plus_v1');
    expect(url.searchParams.get('interval')).toBe('monthly');
  });

  test('redirect param is preserved alongside billing params', async ({ page }) => {
    // Signup with redirect and billing params
    await page.goto(`/signup?product=${PLAN.product}&interval=yearly&redirect=/dashboard`);
    await waitForAppReady(page);

    // Verify all params are present
    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe(PLAN.product);
    expect(url.searchParams.get('interval')).toBe('yearly');
    expect(url.searchParams.get('redirect')).toBe('/dashboard');

    // Check signin link preserves all params
    const signinLink = page.getByRole('link', { name: /sign in|have an account/i });
    await signinLink.click();
    await expect(page).toHaveURL(/\/signin\?/);

    const signinUrl = new URL(page.url());
    expect(signinUrl.searchParams.get('product')).toBe(PLAN.product);
    expect(signinUrl.searchParams.get('interval')).toBe('yearly');
    expect(signinUrl.searchParams.get('redirect')).toBe('/dashboard');
  });

  test('email param is preserved with billing params', async ({ page }) => {
    const testEmail = 'prefill@example.com';
    await page.goto(
      `/signup?email=${encodeURIComponent(testEmail)}&product=${PLAN.product}&interval=yearly`
    );
    await waitForAppReady(page);

    // Email should be prefilled
    await expect(page.getByTestId('signup-email-input')).toHaveValue(testEmail);

    // URL should have all params
    const url = new URL(page.url());
    expect(url.searchParams.get('email')).toBe(testEmail);
    expect(url.searchParams.get('product')).toBe(PLAN.product);
    expect(url.searchParams.get('interval')).toBe('yearly');
  });
});

test.describe('Pending Plan Intent - Sign In Flow', () => {
  test('signin page displays with preserved billing params', async ({ page }) => {
    await page.goto(`/signin?product=${PLAN.product}&interval=yearly`);
    await waitForAppReady(page);

    // Either sign-in surface must be present (plain form, or the tabbed
    // passwordless-first variant when magic links / WebAuthn are enabled)
    const signinForm = page.getByTestId('signin-form');
    const passwordTab = page.getByRole('tab', { name: /password/i });
    await expect(signinForm.or(passwordTab).first()).toBeVisible();

    // URL should still have billing params
    const url = new URL(page.url());
    expect(url.searchParams.get('product')).toBe(PLAN.product);
    expect(url.searchParams.get('interval')).toBe('yearly');
  });

  test('login request includes billing params', async ({ page }) => {
    const getRequestBody = observePostBody(page, '/auth/login');

    await page.goto(`/signin?product=${PLAN.product}&interval=yearly`);
    await waitForAppReady(page);

    // Credentials don't need to be valid — only the request body is under test
    await fillSignInForm(page, 'plan-intent-login-body@test.onetimesecret.com', 'testpass');
    await Promise.all([
      page.waitForResponse((response) => response.url().includes('/auth/login')),
      submitSignInForm(page),
    ]);

    // Verify billing params were included
    const requestBody = getRequestBody();
    expect(requestBody, 'the SPA sent no body to /auth/login').not.toBeNull();
    expect(requestBody?.product).toBe(PLAN.product);
    expect(requestBody?.interval).toBe('yearly');
  });
});

test.describe('Pending Plan Intent - Verify Account Flow', () => {
  test('verify account page handles missing key gracefully', async ({ page }) => {
    await page.goto('/verify-account');
    await waitForAppReady(page);

    // Should show missing key message
    const missingKeyMessage = page.locator('text=/missing.*key|verification.*link/i');
    await expect(missingKeyMessage.first()).toBeVisible();
  });

  test('verify account page handles invalid key', async ({ page }) => {
    await page.goto('/verify-account?key=invalid-key-12345');
    await waitForAppReady(page);

    // Should show error message (after API call fails)
    const errorMessage = page.locator('[role="alert"]');
    await expect(errorMessage).toBeVisible({ timeout: 10000 });
  });

  test('verify account page shows signin link on error', async ({ page }) => {
    await page.goto('/verify-account?key=invalid-key-12345');
    await waitForAppReady(page);

    // Wait for verification to complete (with error)
    await page.waitForSelector('[role="alert"]', { timeout: 10000 }).catch(() => {});

    // Sign in link should be visible
    const signinLink = page.getByRole('link', { name: /sign in/i });
    await expect(signinLink).toBeVisible();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// The full journey (#4306): signup → real email → fresh browser → plans page
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Plan intent journey (issue #4306)', () => {
  // Signup + async mail delivery + verify + signin is a long journey; the
  // 60s suite default is not enough headroom for the mail poll.
  test.slow();

  test.beforeAll(async () => {
    expect(
      await isMailpitReachable(),
      `Mailpit is not reachable at ${MAILPIT_URL}. The verification-link steps ` +
        'cannot run without it. Start it (podman compose -f ' +
        'docker/compose/docker-compose.mailpit.yml up -d) or point MAILPIT_URL ' +
        'at a running instance.'
    ).toBe(true);
  });

  test('a plan chosen before signup survives verification in a fresh browser', async ({
    browser,
    baseURL,
    page,
  }) => {
    const { email, requestBody } = await submitSignup(
      page,
      `/signup?product=${PLAN.product}&interval=${PLAN.interval}`,
      SIGNUP_OPTIONS
    );

    // The selection has to reach the SERVER at signup — that is what makes
    // it survive a browser that never saw this tab. before_create_account
    // captures request params into the session; after_create_account
    // persists them as pending_plan_intent on the Customer.
    expect(requestBody, 'the SPA sent no body to /auth/create-account').not.toBeNull();
    expect(requestBody?.product).toBe(PLAN.product);
    expect(requestBody?.interval).toBe(PLAN.interval);

    const verifyPage = await verifyInFreshContext(browser, email, baseURL!);

    try {
      // verify-account validated the plan against the catalog and put the
      // plans destination in its JSON response; the SPA appended it to the
      // sign-in URL. If this comes back null, look at BILLING_ENABLED and
      // whether the catalog resolves the plan — an invalid intent is
      // (correctly) dropped here.
      await verifyPage.waitForURL(/\/signin\?/);
      expect(
        new URL(verifyPage.url()).searchParams.get('redirect'),
        'verify-account must mint the plans redirect for a valid plan intent ' +
          '(requires BILLING_ENABLED=true and a catalog that resolves ' +
          `${PLAN.product}/${PLAN.interval} on the target)`
      ).toBe(EXPECTED_SIGNIN_REDIRECT);

      // Registered BEFORE the navigation settles: this response is the tail
      // end of the whole feature. The stored intent is no longer consumed at
      // login-response build — the auth hooks only PEEK — it is consumed by
      // BillingController#subscription_status when the plans page fetches
      // subscription state on mount. A test that tears the context down as
      // soon as the URL looks right aborts that in-flight fetch and the
      // intent is never consumed at all (observed: entitlements/plans
      // requests logged as aborted in the trace, zero consumption lines in
      // the server log). Waiting for the response is what makes this test
      // cover the deferred-consumption handoff, not just the redirect.
      const subscriptionSettled = verifyPage.waitForResponse(
        (r) => /\/billing\/api\/org\/[^/]+\/subscription/.test(r.url()),
        { timeout: 30_000 }
      );

      await signIn(verifyPage, email, SIGNUP_OPTIONS.password);

      // The login response replayed the stored intent as billing_redirect,
      // and the SPA resolved it to the org-scoped plans page. Waited on the
      // PATHNAME: the /signin URL we are leaving already contains
      // "/billing/plans" in its query, so a glob or whole-URL regex would be
      // satisfied before the navigation happens. Three segments, not two —
      // /billing/plans (the guard route) rewrites to /billing/:extid/plans
      // and must carry the query with it.
      await waitForPathname(verifyPage, /^\/billing\/[^/]+\/plans$/);

      const landed = new URL(verifyPage.url());
      expect(landed.searchParams.get('product')).toBe(PLAN.product);
      expect(landed.searchParams.get('interval')).toBe(PLAN.interval);
      await waitForAppReady(verifyPage);

      // The plans-flow entry point answered — the handoff the journey exists
      // to deliver actually completed, and with it the deferred intent
      // consumption on the server.
      expect((await subscriptionSettled).status()).toBe(200);

      // Bonus, behaviour-level: PlanSelector consumed the query — the
      // billing interval toggle preselects Monthly. Honest caveat: 'month'
      // is also the component's default, so on its own this can pass
      // vacuously; it is asserted AFTER the subscription response above,
      // i.e. after onMounted's query handling has provably run.
      await expect(
        verifyPage.getByTestId('billing-interval-month'),
        'PlanSelector should preselect the Monthly interval from the query'
      ).toHaveAttribute('aria-pressed', 'true', { timeout: 30_000 });
    } finally {
      await verifyPage.context().close();
    }
  });

  /**
   * Negative case: a plan that passes the ID format check but resolves to
   * nothing in the catalog. Billing::PlanResolver rejects it at verify-time,
   * the stored intent is deleted, and the journey must degrade to the
   * default landing — no billing redirect, no error page. This pins the
   * end-to-end OUTCOME, not which layer rejects the value.
   */
  test('an unknown plan degrades to the default landing, not an error', async ({
    browser,
    baseURL,
    page,
  }) => {
    const { email, requestBody } = await submitSignup(
      page,
      '/signup?product=nonexistent_plan_v9&interval=monthly',
      SIGNUP_OPTIONS
    );

    // The SPA forwards the selection as-is; validation is the server's job.
    expect(requestBody?.product).toBe('nonexistent_plan_v9');

    const verifyPage = await verifyInFreshContext(browser, email, baseURL!);

    try {
      await verifyPage.waitForURL(/\/signin/);

      // The invalid intent must NOT be echoed into the sign-in URL.
      expect(new URL(verifyPage.url()).searchParams.get('redirect')).toBeNull();

      await signIn(verifyPage, email, SIGNUP_OPTIONS.password);

      // Signin succeeds and lands where a journey with no plan at all would:
      // the app's own root, not /billing/* and not an error page.
      await expect(verifyPage).not.toHaveURL(/\/signin/, { timeout: 30_000 });
      await waitForAppReady(verifyPage);

      const landed = new URL(verifyPage.url());
      expect(landed.pathname).toMatch(/^\/(dashboard)?$/);
      expect(landed.pathname).not.toContain('/billing');
    } finally {
      await verifyPage.context().close();
    }
  });
});
