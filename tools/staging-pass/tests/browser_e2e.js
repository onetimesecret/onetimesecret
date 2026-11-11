// Real-browser pass over the core secret path, through the proxy, in full
// mode: sign in with the form, create a secret, open its link in a second
// browser context, reveal it, see the receipt change.
//
//   node browser_e2e.js <email> <password> <label>
//
// Prints one JSON object per check. Chromium does not trust the staging CA,
// so certificate errors are ignored here; TLS itself is checked by suite_proxy.
const { chromium } = require('playwright');
const fs = require('fs');

const [email, password, label] = process.argv.slice(2);
const BASE = 'https://secrets.staging.test';
const out = [];
const check = (id, desc, pass, observed) => {
  out.push({ suite: `browser-${label}`, id, desc, pass: !!pass, observed });
  console.log(`[${pass ? 'PASS' : 'FAIL'}] ${id} ${desc}${observed === undefined ? '' : ' :: ' + JSON.stringify(observed).slice(0, 300)}`);
};

function watch(page, bag) {
  page.on('response', (r) => {
    const u = new URL(r.url());
    if (u.origin !== BASE) return;
    if (r.status() >= 400) bag.bad.push(`${r.status()} ${r.request().method()} ${u.pathname.replace(/[a-z0-9]{40,}/g, ':id')}`);
    if (u.pathname.startsWith('/api/')) bag.api.push(`${r.status()} ${r.request().method()} ${u.pathname.replace(/[a-z0-9]{40,}/g, ':id')}`);
  });
  page.on('console', (m) => { if (m.type() === 'error') bag.console.push(m.text().slice(0, 200)); });
  page.on('pageerror', (e) => bag.console.push('pageerror: ' + String(e).slice(0, 200)));
}

(async () => {
  const browser = await chromium.launch({ args: ['--no-proxy-server'] });
  const bag = { bad: [], api: [], console: [] };
  const secretText = `browser secret ${Date.now()} ünicode`;
  let failed = false;
  try {
    // ---- creator
    const creator = await browser.newContext({ ignoreHTTPSErrors: true });
    const page = await creator.newPage();
    watch(page, bag);
    await page.goto(BASE + '/signin');
    await page.locator('html[data-app-ready="true"]').waitFor({ state: 'attached', timeout: 30000 });
    const form = page.getByTestId('signin-form');
    const tab = page.getByRole('tab', { name: /password/i });
    await form.or(tab).first().waitFor({ timeout: 20000 });
    if (await tab.isVisible()) {
      await tab.click();
      await page.getByTestId('password-email-input').fill(email);
      await page.getByTestId('password-input').fill(password);
      await page.getByTestId('password-submit').click();
    } else {
      await page.getByTestId('signin-email-input').fill(email);
      await page.getByTestId('signin-password-input').fill(password);
      await page.getByTestId('signin-submit').click();
    }
    await page.waitForURL((u) => !u.pathname.startsWith('/signin'), { timeout: 30000 });
    const cookies = await creator.cookies(BASE);
    const sess = cookies.find((c) => c.name === 'onetime.session');
    check('B01', 'sign-in form through the proxy reaches the signed-in app with a Secure, HttpOnly session cookie',
      sess && sess.secure && sess.httpOnly, { url: new URL(page.url()).pathname, sameSite: sess && sess.sameSite });

    // The signed-in dashboard carries the create form (a bare textarea);
    // the anonymous homepage's has a test id.
    await page.locator('html[data-app-ready="true"]').waitFor({ state: 'attached', timeout: 30000 });
    const input = page.getByTestId('secret-content-input').or(page.locator('textarea')).first();
    await input.waitFor({ timeout: 30000 });
    await input.fill(secretText);
    const concealed = page.waitForResponse((r) => r.request().method() === 'POST' && new URL(r.url()).pathname.endsWith('/secret/conceal'));
    await page.getByTestId('split-button-submit').click();
    const resp = await concealed;
    const body = await resp.json().catch(() => ({}));
    const receiptId = body.record && body.record.receipt && body.record.receipt.identifier;
    const secretId = body.record && body.record.secret && body.record.secret.identifier;
    check('B02', 'the form creates a secret through the session API (CSRF token sent by the SPA)',
      resp.ok() && receiptId && secretId, { status: resp.status(), path: new URL(resp.url()).pathname, owner: body.record && !!body.record.receipt.owner_id });
    await page.waitForURL((u) => u.pathname === `/receipt/${receiptId}`, { timeout: 6000 }).catch(() => page.goto(`${BASE}/receipt/${receiptId}`));
    const link = page.getByTestId('receipt-secret-link');
    await link.waitFor({ timeout: 20000 });
    const shown = await page.evaluate((id) => {
      const hit = (s) => typeof s === 'string' && s.includes(`secrets.staging.test/secret/${id}`);
      return [...document.querySelectorAll('a, input, textarea, [data-testid="receipt-secret-link"] *')]
        .some((e) => hit(e.href) || hit(e.value) || hit(e.textContent) || hit(e.getAttribute('title')));
    }, secretId);
    check('B03', 'the receipt page carries the share link on the public host', shown);

    // ---- recipient, separate browser context (no session)
    const recipient = await browser.newContext({ ignoreHTTPSErrors: true });
    const rpage = await recipient.newPage();
    watch(rpage, bag);
    await rpage.goto(`${BASE}/secret/${secretId}`);
    const reveal = rpage.getByTestId('secret-reveal-submit').first();
    await reveal.waitFor({ timeout: 30000 });
    const revealed = rpage.waitForResponse((r) => r.request().method() === 'POST' && /\/reveal$/.test(new URL(r.url()).pathname));
    await reveal.click();
    const rresp = await revealed;
    const rbody = await rresp.json().catch(() => ({}));
    check('B04', 'the recipient reveals it in another browser context',
      rresp.ok() && rbody.record && rbody.record.secret_value === secretText, { status: rresp.status(), path: new URL(rresp.url()).pathname.replace(secretId, ':id') });
    await rpage.getByText(secretText, { exact: false }).first().waitFor({ timeout: 15000 }).then(
      () => check('B05', 'and the page displays the secret text', true),
      async () => {
        const vals = await rpage.locator('textarea, input').evaluateAll((els) => els.map((e) => e.value));
        check('B05', 'and the page displays the secret text', vals.some((v) => v && v.includes(secretText)), vals.map((v) => (v || '').length));
      });
    await rpage.reload();
    await rpage.locator('html[data-app-ready="true"]').waitFor({ state: 'attached', timeout: 30000 });
    await rpage.waitForTimeout(1500);
    const again = await rpage.getByText(secretText, { exact: false }).count();
    check('B06', 'reloading the link no longer shows it', again === 0, again);

    // ---- creator sees the receipt change
    await page.reload();
    await page.locator('html[data-app-ready="true"]').waitFor({ state: 'attached', timeout: 30000 });
    const st = await page.evaluate(async (id) => {
      const r = await fetch(`/api/v3/receipt/${id}`, { headers: { Accept: 'application/json' } });
      const d = await r.json();
      return { status: r.status, state: d.record && d.record.state, revealed: d.record && d.record.is_revealed };
    }, receiptId);
    check('B07', "the creator's session reads the receipt as revealed", st.status === 200 && st.state === 'revealed' && st.revealed === true, st);

    const non429 = bag.bad.filter((x) => !x.startsWith('429'));
    const n429 = bag.bad.length - non429.length;
    // The reload of a consumed secret answers 404 by design.
    const unexpected = non429.filter((x) => !/^404 (GET|POST) \/api\/v[23]\/(guest\/)?secret\/:id/.test(x));
    check('B08', 'no unexpected 4xx/5xx on same-origin requests during the journey', unexpected.length === 0, unexpected.slice(0, 8));
    check('B09', 'no request was throttled by the proxy during a single-user journey', n429 === 0, { throttled: n429, sample: bag.bad.filter((x) => x.startsWith('429')).slice(0, 4) });
    const cons = bag.console.filter((x) => !/status of 404/.test(x));   // the consumed-secret reload above
    check('B10', 'no console errors besides the expected 404 on the consumed secret', cons.length === 0, cons.slice(0, 5));
    console.log('[NOTE] api calls: ' + JSON.stringify([...new Set(bag.api)].slice(0, 30)));
  } catch (e) {
    failed = true;
    check('B99', 'browser journey completed', false, String(e).slice(0, 400));
  } finally {
    await browser.close();
    const results = (process.env.STAGING_STATE || `${process.env.STAGING_ROOT || '/srv/ots-staging'}/state`) + '/results';
    fs.mkdirSync(results, { recursive: true });
    fs.writeFileSync(`${results}/browser-${label}.jsonl`, out.map((o) => JSON.stringify(o)).join('\n') + '\n');
    process.exit(failed || out.some((o) => !o.pass) ? 1 : 0);
  }
})();
