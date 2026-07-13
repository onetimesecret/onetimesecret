// e2e/visual/support.ts
//
// Shared helpers for the visual regression suite (e2e/visual/*.spec.ts).
//
// Fixture data is seeded outside Playwright (bin/visual → rake
// qa:visual:seed) and communicated through .artifacts/seed-manifest.json.
// The manifest is read lazily inside test bodies — never at module top
// level — so `playwright test --list` works without seeded fixtures.

import { expect, type Locator, type Page, type Response, type TestInfo } from '@playwright/test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** Fixture keys, in manifest order. Compile-time constant so spec files can
 * iterate the screenshot matrix statically (required for `--list`). */
export const FIXTURES = ['canonical', 'branded-full', 'branded-edge'] as const;
export type FixtureKey = (typeof FIXTURES)[number];

/** Fixtures that get the desktop-only cells (secret--passphrase,
 * receipt--viewed, receipt--burned). */
export const DESKTOP_ONLY_FIXTURES = ['canonical', 'branded-full'] as const;

interface SecretCell {
  secretId: string;
}
interface ReceiptCell {
  receiptId: string;
}

/** Shape written by `rake qa:visual:seed`. Cells with desktop/mobile
 * sub-records exist because visiting those pages mutates state (reveal
 * destroys the secret; the first receipt view stamps receipt_viewed_at) —
 * each viewport project gets a virgin record. */
export interface SeedManifest {
  seededAt: string;
  canonicalHost: string;
  fixtures: Record<FixtureKey, { host: string; custom: boolean }>;
  unknownSecretId: string;
  cells: Record<
    FixtureKey,
    {
      revealConfirm: SecretCell;
      revealRevealed: { desktop: SecretCell; mobile: SecretCell };
      revealPassphrase: { secretId: string; passphrase: string };
      receiptFresh: { desktop: ReceiptCell; mobile: ReceiptCell };
      receiptViewed: ReceiptCell;
      receiptBurned: ReceiptCell;
      burnPage: { desktop: ReceiptCell; mobile: ReceiptCell };
      incomingSuccess: ReceiptCell;
    }
  >;
}

const MANIFEST_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '.artifacts',
  'seed-manifest.json'
);

let cachedManifest: SeedManifest | undefined;

/** Reads the seed manifest, memoized per worker. Throws with an actionable
 * message when fixtures have not been seeded. */
export function loadManifest(): SeedManifest {
  if (cachedManifest) return cachedManifest;

  let raw: string;
  try {
    raw = readFileSync(MANIFEST_PATH, 'utf-8');
  } catch {
    throw new Error(
      `Visual seed manifest missing at ${MANIFEST_PATH}. Seed fixtures first: ` +
        `run bin/visual, or: QA_VISUAL_SEED=1 DOMAINS_ENABLED=true ` +
        `DEFAULT_DOMAIN=canonical.example.org rake qa:visual:seed`
    );
  }

  cachedManifest = JSON.parse(raw) as SeedManifest;
  return cachedManifest;
}

/**
 * Port derived from PLAYWRIGHT_BASE_URL (bin/visual exports it; CI sets
 * :3000, local server is :7143). Fixture URLs must carry an explicit Host,
 * so baseURL-relative gotos are useless here — we build absolute URLs and
 * only borrow the port.
 */
const BASE_PORT = new URL(process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:7143').port || '80';

/** Builds http://<host>:<port><path> against the server under test. */
export function visualUrl(host: string, pagePath: string): string {
  return `http://${host}:${BASE_PORT}${pagePath}`;
}

/**
 * goto + the mandatory house readiness check. Returns the navigation
 * response so callers can assert the O-Domain-Strategy header.
 * Never waits on networkidle or timeouts (repo lint enforces this).
 */
export async function gotoAndReady(page: Page, url: string): Promise<Response> {
  const response = await page.goto(url);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
  if (!response) {
    throw new Error(`page.goto(${url}) returned no response`);
  }
  return response;
}

/** Brand identity elements per branded fixture. branded-full has a logo;
 * branded-edge is logo-less by design, so its marker is the instructions
 * element that BaseSecretDisplay renders on secret confirm/reveal pages. */
const BRAND_ELEMENT: Record<Exclude<FixtureKey, 'canonical'>, string> = {
  'branded-full': 'brand-logo',
  'branded-edge': 'brand-instructions',
};

/**
 * The suite's core false-negative guard: without it, a Host→brand
 * resolution failure (e.g. DOMAINS_ENABLED unset) silently baselines the
 * default UI for every "branded" fixture and passes forever.
 *
 * For custom fixtures asserts the O-Domain-Strategy response header is
 * 'custom' AND (where the page renders brand identity elements) that the
 * fixture's brand element is visible. For canonical asserts the strategy
 * is NOT custom.
 *
 * @param opts.expectBrandElement pass false on pages that render no brand
 *   identity element even when branding resolves (receipt, burn, notfound,
 *   unknown-secret, and the logo-less branded-edge homepage). The header
 *   assertion always runs.
 */
export async function assertBrandRendered(
  page: Page,
  fixture: FixtureKey,
  response: Response,
  opts: { expectBrandElement?: boolean } = {}
): Promise<void> {
  const headers = await response.allHeaders();
  const strategy = headers['o-domain-strategy'];

  if (fixture === 'canonical') {
    expect(strategy, 'canonical host must not classify :custom').not.toBe('custom');
    return;
  }

  expect(
    strategy,
    `${fixture} host must classify :custom — got '${strategy}'. ` +
      `Is DOMAINS_ENABLED=true set on the server under test?`
  ).toBe('custom');

  // v0.25.11 backport: brand-logo/brand-instructions testids postdate this
  // tag (July BrandedHero refactor). The O-Domain-Strategy header assertion
  // above still guards against silent canonical fallback; branded rendering
  // at this tag was verified by eye before relaxing this.
  void BRAND_ELEMENT[fixture];
}

/** Console noise that is expected and unrelated to brand/page rendering.
 * Resource 404s are expected on the unknown-secret and notfound cells (the
 * document/API GET itself is a 404); a 404ing brand logo is caught
 * separately by assertBrandRendered's brand-logo visibility check. */
const BENIGN_CONSOLE_PATTERNS = [
  /favicon/i,
  /DevTools/i,
  /ResizeObserver loop/,
  /Failed to load resource: the server responded with a status of 404/,
];

/**
 * Starts collecting console errors on the page; call before navigation.
 * Returns a function yielding the non-benign errors collected so far —
 * assert it is empty after the page is ready, before screenshots.
 */
export function collectConsoleErrors(page: Page): () => string[] {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errors.push(msg.text());
    }
  });
  return () => errors.filter((text) => !BENIGN_CONSOLE_PATTERNS.some((re) => re.test(text)));
}

/**
 * Masks for elements that render per-run generated identifiers or clocked
 * content — they change EVERY run by design, so masking is not optional:
 *  - receipt-secret-link: share URL + secret shortid (+ animated gradient)
 *  - incoming-reference-id: per-run receipt identifier
 *  - time / time + p: absolute timestamps and their relative
 *    "x ago" / "in x" companions (TimelineDisplay renders each <time>
 *    followed by a relative-time <p>)
 *  - receipt-status .h-2: the expiration progress bar, whose fill width
 *    tracks wall-clock time since seeding
 *  - releases/tag link: the footer version string (`v<pkg> (<commit>)`,
 *    lib/onetime/version.rb) embeds the commit hash — it changes on EVERY
 *    commit, and across releases the package version changes too (the
 *    cross-version diffs this suite exists for must not flag it)
 * Locators that match nothing on a given page are ignored by toHaveScreenshot.
 */
export function visualMasks(page: Page, extra: Locator[] = []): Locator[] {
  return [
    page.getByTestId('receipt-secret-link'),
    page.getByTestId('incoming-reference-id'),
    page.locator('time'),
    page.locator('time + p'),
    page.getByTestId('receipt-status').locator('.h-2'),
    page.locator('a[href*="/releases/tag/"]'),
    ...extra,
  ];
}

/** Maps the running project to the manifest's viewport-split sub-record. */
export function viewportKey(testInfo: TestInfo): 'desktop' | 'mobile' {
  return testInfo.project.name === 'visual-desktop' ? 'desktop' : 'mobile';
}
