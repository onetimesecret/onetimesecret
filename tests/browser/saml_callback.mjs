// Invoked only by the Ruby browser lane spec, which owns all fixture servers.
import { chromium, firefox, webkit, expect } from '@playwright/test';
import { existsSync } from 'node:fs';

const { origins, proxy, scenarios } = JSON.parse(process.argv[2]);
const callbackPath = '/auth/sso/saml/callback';
const cookieName = 'saml.browser.session';
const watchdog = setTimeout(() => {
  console.error('Browser harness exceeded 180 seconds');
  console.error(
    JSON.stringify(
      results.map(({ browser, scenario, status, error, phase }) => ({
        browser,
        scenario,
        status,
        error,
        phase,
      }))
    )
  );
  process.exit(1);
}, 180_000);
const results = [];
const engines = { chromium, firefox, webkit };
const missingBrowsers = Object.entries(engines)
  .filter(([, engine]) => !existsSync(engine.executablePath()))
  .map(([name]) => name);

async function newContext(browser) {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    proxy: { server: proxy },
  });
  // Only the explicit fixture origins reach the local CONNECT proxy. Neither
  // browser traffic nor that proxy can resolve/contact an external destination.
  await context.route('**/*', (route) => {
    const origin = new URL(route.request().url()).origin;
    return Object.values(origins).includes(origin) ? route.continue() : route.abort();
  });
  return context;
}

async function sessionCookie(context, base) {
  const cookies = (await context.cookies(base)).filter((cookie) => cookie.name === cookieName);
  expect(cookies).toHaveLength(1);
  return cookies[0];
}

async function readEvidence(page) {
  return JSON.parse(await page.getByTestId('evidence').textContent());
}

function checkHost(host, scenario, base, rewrite) {
  const publicHost = new URL(base).hostname;
  const originalAuthority = new URL(scenario.proxy ? origins.origin : base).host;
  const rewritten = scenario.proxy && rewrite;
  expect(host.detectedHost).toBe(publicHost);
  expect(host.displayHost).toBe(publicHost);
  expect(host.strategy).toBe(scenario.surface === 'tenant' ? 'custom' : 'canonical');
  expect(host.tenantResolved).toBe(scenario.surface === 'tenant');
  expect(host.rackHost).toBe(
    new URL(rewritten ? base : scenario.proxy ? origins.origin : base).hostname
  );
  expect(host.rackBase).toBe(rewritten ? base : scenario.proxy ? origins.origin : base);
  expect(host.originalHost).toBe(originalAuthority);
  expect(host.rewritten).toBe(rewritten);
  expect(host.forwardedHostRemoved).toBe(true);
  expect(host.scope).toEqual([
    scenario.proxy ? origins.origin : base,
    publicHost,
    publicHost,
    callbackPath,
  ]);
}

// Run real browser GETs before the rightful redirected GET: another session
// cannot consume its handle; even copying the pending cookie to another served
// host cannot cross the staged public-host scope. The rightful GET must still
// succeed afterwards, proving the two refusals did not consume the transaction.
async function checkBindingControls(browser, base, location, pending) {
  const other = base === origins.canonical ? origins.tenant : origins.canonical;
  const anonymous = await newContext(browser);
  const wrongHost = await newContext(browser);
  try {
    const anonymousPage = await anonymous.newPage();
    anonymousPage.setDefaultTimeout(10_000);
    const denied = await anonymousPage.goto(`${base}${location}`);
    expect(denied.status()).toBe(401);
    const missingSession = await readEvidence(anonymousPage);
    expect(missingSession.failure).toBe('saml_no_pending_request');
    expect(missingSession.originalSession).toBe(false);

    await wrongHost.addCookies([{ ...pending, domain: new URL(other).hostname }]);
    const wrongHostPage = await wrongHost.newPage();
    wrongHostPage.setDefaultTimeout(10_000);
    const wrongScope = await wrongHostPage.goto(`${other}${location}`);
    expect(wrongScope.status()).toBe(401);
    const scoped = await readEvidence(wrongHostPage);
    expect(scoped.originalSession).toBe(true);
    expect(scoped.pendingRequest).toBe(true);
    expect(scoped.failure).toBe('saml_callback_missing');
    expect(scoped.host.scope[0]).toBe(origins.origin);
    expect(scoped.host.scope[1]).toBe(new URL(other).hostname);
    return 2;
  } finally {
    await anonymous.close();
    await wrongHost.close();
  }
}

try {
  if (missingBrowsers.length > 0) {
    throw new Error(
      `Required Playwright browsers are not installed: ${missingBrowsers.join(', ')}. ` +
        'Run pnpm playwright:install.'
    );
  }
  for (const [name, engine] of Object.entries(engines)) {
    const browser = await engine.launch({ headless: true, timeout: 15_000 });
    try {
      for (const scenario of scenarios) {
        const { sameSite } = scenario;
        const base = origins[scenario.surface];
        const context = await newContext(browser);
        let phase = 'start';
        try {
          const page = await context.newPage();
          page.setDefaultTimeout(10_000);
          const start = await page.goto(`${base}/start?scenario=${scenario.id}`);
          expect(start.status()).toBe(200);
          const initial = await sessionCookie(context, base);
          expect(initial.secure).toBe(true);
          expect(initial.httpOnly).toBe(true);
          expect(initial.sameSite).toBe('Lax');
          expect(initial.domain).toBe(new URL(base).hostname);
          if (sameSite !== 'Lax') await context.addCookies([{ ...initial, sameSite }]);
          phase = 'initiation';
          // WebKit does not expose this request phase's successful redirect
          // response reliably. Observe its actual IdP navigation below instead.
          const initiationPromise = scenario.initiationRefusal
            ? page.waitForResponse(
                (response) =>
                  response.url() === `${base}/auth/sso/saml` &&
                  response.request().method() === 'POST'
              )
            : null;
          await page.getByRole('button', { name: 'Start SAML sign-in' }).click();
          if (scenario.initiationRefusal) {
            const initiation = await initiationPromise;
            // B-01: documented rewrite-off limitation, not a new defect. The
            // port-less display-host allowance refuses this public Origin;
            // preserve public Host or opt in to rewriting to initiate.
            expect(initiation.status()).toBe(scenario.initiationRefusal);
            expect((await initiation.allHeaders()).location).toBeUndefined();
            expect((await sessionCookie(context, base)).value).toBe(initial.value);
            await page.goto(`${base}/probe`);
            const observed = await readEvidence(page);
            expect(observed.originalSession).toBe(true);
            expect(observed.pendingRequest).toBe(false);
            expect(observed.host.strategy).toBe('canonical');
            expect(observed.host.rackBase).toBe(origins.origin);
            expect(observed.host.rewritten).toBe(false);
            results.push({
              browser: name,
              version: browser.version(),
              scenario: scenario.id,
              sameSite,
              status: 'passed',
              bindingChecks: 0,
              replayChecks: 0,
              ...observed,
            });
            continue;
          }

          await expect(page).toHaveURL(
            new RegExp(`^${origins.idp.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/idp`)
          );
          const issued = await sessionCookie(context, base);
          expect(issued.value).toBe(initial.value);
          // Production Session reissues Lax in request phase; modify only the
          // browser's cookie policy, not its session id or pending transaction.
          const pending = { ...issued, sameSite };
          if (sameSite !== 'Lax') await context.addCookies([pending]);
          if (scenario.id === 'unconfigured-origin') {
            const unconfigured = new URL(page.url());
            unconfigured.host = new URL(origins.unconfigured_idp).host;
            await page.goto(unconfigured.href);
          }
          phase = 'callback';
          const postPromise = page.waitForResponse(
            (response) =>
              response.url() === `${base}${callbackPath}` && response.request().method() === 'POST'
          );
          let bindingChecks = 0;

          const getPromise = scenario.refusal
            ? null
            : page.waitForResponse(
                (response) =>
                  response.url().startsWith(`${base}${callbackPath}?`) &&
                  response.request().method() === 'GET'
              );
          await page
            .getByRole('button', { name: 'Return signed assertion' })
            .click({ noWaitAfter: true });
          const post = await postPromise;
          const postHeaders = await post.allHeaders();
          expect(postHeaders['set-cookie']).toBeUndefined();
          expect(postHeaders['referrer-policy']).toBe('no-referrer');
          expect(postHeaders['cache-control']).toBe('no-store');
          let observed;
          let replayChecks = 0;
          if (scenario.refusal) {
            expect(post.status()).toBe(scenario.refusal);
            expect(postHeaders.location).toBeUndefined();
            await page.waitForURL(`${base}${callbackPath}`, { waitUntil: 'load' });
            expect((await sessionCookie(context, base)).value).toBe(pending.value);
            await page.goto(`${base}/probe`);
            observed = await readEvidence(page);
            expect(observed.originalSession).toBe(true);
            expect(observed.pendingRequest).toBe(true);
          } else {
            expect(post.status()).toBe(303);
            const location = postHeaders.location;
            expect(location).toMatch(/^\/auth\/sso\/saml\/callback\?saml_handle=[0-9a-f]{64}$/);
            if (scenario.bindingControls) {
              try {
                expect((await sessionCookie(context, base)).value).toBe(pending.value);
                bindingChecks = await checkBindingControls(browser, base, location, pending);
                expect(bindingChecks).toBe(2);
              } finally {
                // Release the bounded fixture gate; the original browser still
                // completes its real redirect with browser-selected cookies.
                const release = await context.request.post(`${base}/__fixture/release`);
                expect(release.status()).toBe(200);
              }
            }
            phase = 'completion';
            await expect(page.getByRole('heading')).toHaveText(
              sameSite === 'Strict' ? 'Refused' : 'Assertion accepted'
            );

            const completion = await getPromise;
            expect(completion.status()).toBe(sameSite === 'Strict' ? 401 : 200);
            const headers = await completion.allHeaders();
            expect(headers['referrer-policy']).toBe('no-referrer');
            expect(headers['cache-control']).toBe('no-store');
            observed = await readEvidence(page);
            // WebKit does not expose Cookie request headers to Playwright.
            // These are observations at ingress and below the real Boundary.
            expect(observed.postBoundaryCookie).toBe(false);
            expect(observed.postSession).toBe(false);
            expect(observed.method).toBe('GET');
            expect(observed.cookie).toBe(sameSite !== 'Strict');
            expect(observed.originalSession).toBe(sameSite !== 'Strict');
            expect(observed.pendingRequest).toBe(false);
            expect(observed.failure).toBe(sameSite === 'Strict' ? 'saml_no_pending_request' : null);
            checkHost(observed.postHost, scenario, base, scenario.postRewrite);
            checkHost(observed.host, scenario, base, scenario.getRewrite);
            expect(observed.host.scope).toEqual(observed.postHost.scope);
            await page.getByRole('link', { name: 'Leave callback' }).click();
            await expect(page.getByTestId('referrer')).toHaveText('absent');
            if (sameSite !== 'Strict') {
              expect((await sessionCookie(context, base)).value).toBe(pending.value);
              const replay = await page.goto(`${base}${location}`);
              expect(replay.status()).toBe(401);
              await expect(page.getByRole('heading')).toHaveText('Refused');
              expect((await readEvidence(page)).failure).toBe('saml_callback_missing');
              replayChecks = 1;
            }
          }
          expect(observed.postCookie).toBe(sameSite === 'None');
          expect(observed.postAuthenticated).toBe(false);
          expect(observed.postOrigin).toBe(
            scenario.id === 'unconfigured-origin' ? origins.unconfigured_idp : origins.idp
          );
          results.push({
            browser: name,
            version: browser.version(),
            scenario: scenario.id,
            sameSite,
            status: 'passed',
            bindingChecks,
            replayChecks,
            ...observed,
          });
        } catch (error) {
          results.push({
            browser: name,
            version: browser.version(),
            scenario: scenario.id,
            sameSite,
            status: 'failed',
            phase,
            error: String(error && error.message ? error.message : error).split('\n')[0],
            at:
              ((error && error.stack) || '')
                .split('\n')
                .find((line) => line.includes('saml_callback.mjs')) || null,
          });
        } finally {
          const result = results.at(-1);
          console.error(
            JSON.stringify({
              browser: name,
              scenario: scenario.id,
              status: result?.status,
              phase,
              error: result?.error,
              at: result?.at,
            })
          );
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
