// Invoked only by the Ruby lane spec, whose test owns the bounded TLS server.
import { chromium, firefox, webkit, expect } from '@playwright/test';
import { existsSync } from 'node:fs';

const base = process.argv[2];
const idp = process.argv[3];
const watchdog = setTimeout(() => {
  console.error('Browser harness exceeded 90 seconds');
  process.exit(1);
}, 90_000);
const results = [];
try {
  for (const [name, engine] of Object.entries({ chromium, firefox, webkit })) {
    if (!existsSync(engine.executablePath())) {
      if (name === 'chromium')
        throw new Error('Chromium is required: install the pinned Playwright browser');
      results.push({ browser: name, status: 'not installed' });
      continue;
    }
    const browser = await engine.launch({ headless: true, timeout: 15_000 });
    try {
      for (const sameSite of ['Lax', 'None', 'Strict']) {
        const context = await browser.newContext({ ignoreHTTPSErrors: true });
        try {
          // Only these two loopback TLS origins are allowed. No external IdP,
          // telemetry, trace recording, saved cookies or assertion artifacts.
          await context.route('**/*', (route) => {
            const origin = new URL(route.request().url()).origin;
            return [base, idp].includes(origin) ? route.continue() : route.abort();
          });
          const page = await context.newPage();
          page.setDefaultTimeout(10_000);
          await page.goto(`${base}/start`);
          const [initial] = (await context.cookies(base)).filter(
            (c) => c.name === 'saml.browser.session'
          );
          expect(initial.secure).toBe(true);
          expect(initial.sameSite).toBe('Lax');
          if (sameSite !== 'Lax') await context.addCookies([{ ...initial, sameSite }]);
          await page.getByRole('button', { name: 'Start SAML sign-in' }).click();
          await expect(page).toHaveURL(
            new RegExp(`^${idp.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/idp`)
          );
          const [pending] = (await context.cookies(base)).filter(
            (c) => c.name === 'saml.browser.session'
          );
          // Request-phase response reissues the configured Lax cookie; apply
          // the negative-control / compatibility policy to that pending cookie.
          if (sameSite !== 'Lax') await context.addCookies([{ ...pending, sameSite }]);
          const postPromise = page.waitForResponse(
            (r) => r.url() === `${base}/auth/sso/saml/callback` && r.request().method() === 'POST'
          );
          const getPromise = page.waitForResponse(
            (r) =>
              r.url().startsWith(`${base}/auth/sso/saml/callback?`) &&
              r.request().method() === 'GET'
          );
          await page.getByRole('button', { name: 'Return signed assertion' }).click();
          const post = await postPromise;
          expect(post.status()).toBe(303);
          const postHeaders = await post.allHeaders();
          expect(postHeaders['set-cookie']).toBeUndefined();
          expect(postHeaders['referrer-policy']).toBe('no-referrer');
          const postRequestHeaders = await post.request().allHeaders();
          const sentOnPost = (postRequestHeaders.cookie || '').includes('saml.browser.session=');
          expect(sentOnPost).toBe(sameSite === 'None');
          const location = postHeaders.location;
          expect(location).toMatch(/^\/auth\/sso\/saml\/callback\?saml_handle=[0-9a-f]{64}$/);
          await expect(page.getByRole('heading')).toHaveText(
            sameSite === 'Strict' ? 'Refused' : 'Authenticated'
          );
          const completion = await getPromise;
          expect((await completion.allHeaders())['referrer-policy']).toBe('no-referrer');
          expect((await completion.allHeaders())['cache-control']).toBe('no-store');
          const evidence = await page.getByTestId('evidence').textContent();
          const observed = JSON.parse(evidence);
          expect(observed.postCookie).toBe(sameSite === 'None');
          expect(observed.postAuthenticated).toBe(false);
          expect(observed.getMethod).toBe('GET');
          expect(observed.getCookie).toBe(sameSite !== 'Strict');
          expect(observed.originalSession).toBe(sameSite !== 'Strict');
          await page.getByRole('link', { name: 'Leave callback' }).click();
          await expect(page.getByTestId('referrer')).toHaveText('absent');
          if (sameSite !== 'Strict') {
            const replay = await page.goto(`${base}${location}`);
            expect(replay.status()).toBe(401);
            await expect(page.getByRole('heading')).toHaveText('Refused');
          }
          results.push({
            browser: name,
            version: browser.version(),
            sameSite,
            status: 'passed',
            ...observed,
          });
        } finally {
          await context.close();
        }
      }
    } finally {
      await browser.close();
    }
  }
  console.log(JSON.stringify(results));
} finally {
  clearTimeout(watchdog);
}
