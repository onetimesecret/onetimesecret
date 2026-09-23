// e2e/support/diagnostics-guard.ts

/**
 * Global setup for local targets: refuse to start the suite against a
 * server that reports to Sentry. playwright.config.ts registers it when
 * PLAYWRIGHT_BASE_URL is unset or names a local host (loopback, *.localhost,
 * dev.onetime.dev).
 *
 * The webServer block gives the server Playwright spawns
 * DIAGNOSTICS_ENABLED=false, but `reuseExistingServer` (on outside CI)
 * skips spawning when something already answers on the local URL, and
 * PLAYWRIGHT_BASE_URL skips webServer entirely. Either way the suite can
 * end up against a server started by hand from a dev shell, carrying that
 * shell's DIAGNOSTICS_ENABLED=true and real SENTRY_DSN. The env block never
 * reaches it, the RACK_ENV=test gate does not apply to a development or
 * production boot, and the errors the suite provokes on purpose would land
 * in the real Sentry project.
 *
 * So instead of trusting how the server was started, ask it: the bootstrap
 * payload's d9s_enabled is OT.d9s_enabled, the runtime switch that gates
 * every backend capture and the frontend SDK. Playwright runs global setup
 * after webServer is up, so this sees the spawned and the reused server
 * alike. E2E_DIAGNOSTICS_ENABLED=true (the same opt-in the webServer env
 * block honours) skips the check.
 */

import { chromium, type FullConfig } from '@playwright/test';

type BootstrapWindow = Window & { __BOOTSTRAP_ME__?: { d9s_enabled?: boolean } };

export default async function diagnosticsGuard(config: FullConfig): Promise<void> {
  if (process.env.E2E_DIAGNOSTICS_ENABLED === 'true') return;

  const { baseURL, launchOptions } = config.projects[0]?.use ?? {};
  if (!baseURL) throw new Error('diagnostics guard: no baseURL in the Playwright config');

  const browser = await chromium.launch(launchOptions);
  try {
    const page = await browser.newPage();
    await page.goto(baseURL);
    // waitForFunction resolves on a truthy value, so wait for the payload
    // itself, then read the flag (false is the answer we hope for).
    const d9sEnabled = await page
      .waitForFunction(() => Boolean((window as BootstrapWindow).__BOOTSTRAP_ME__), undefined, {
        timeout: 15_000,
      })
      .then(
        () => page.evaluate(() => (window as BootstrapWindow).__BOOTSTRAP_ME__?.d9s_enabled),
        () => undefined
      );

    if (typeof d9sEnabled !== 'boolean') {
      throw new Error(
        `diagnostics guard: ${baseURL} did not expose __BOOTSTRAP_ME__.d9s_enabled, ` +
          'so the suite cannot tell whether it would report to Sentry.'
      );
    }
    if (d9sEnabled) {
      throw new Error(
        `diagnostics guard: the server at ${baseURL} has diagnostics ON and would report ` +
          'the errors this suite provokes to Sentry. This is usually a server started by hand ' +
          'from a shell exporting DIAGNOSTICS_ENABLED=true, which Playwright reused instead of ' +
          'spawning its own. Restart it with DIAGNOSTICS_ENABLED=false (or stop it and let ' +
          'Playwright start one), or set E2E_DIAGNOSTICS_ENABLED=true to run against it anyway.'
      );
    }
  } finally {
    await browser.close();
  }
}
