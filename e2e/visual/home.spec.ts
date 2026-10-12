// e2e/visual/home.spec.ts
//
// Visual baselines for the homepage (/) across canonical and branded hosts.
// Canonical renders the marketing homepage; custom domains render
// BrandedHomepage (hero + form/trust card).
//  - markdown: canonical only, the create form in Markdown mode with the
//    shared sample typed in, so the live preview renders under the editor

import { test, expect } from '@playwright/test';
import {
  FIXTURES,
  assertBrandRendered,
  collectConsoleErrors,
  gotoAndReady,
  loadManifest,
  loadMarkdownSample,
  visualMasks,
  visualUrl,
} from './support';

test.describe('Visual - Homepage', () => {
  for (const fixture of FIXTURES) {
    test(`home--default--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);

      const response = await gotoAndReady(page, visualUrl(manifest.fixtures[fixture].host, '/'));

      // branded-edge is logo-less by design and its homepage hero renders
      // neither brand-logo nor brand-instructions; the O-Domain-Strategy
      // header assertion inside the helper is the guard there.
      await assertBrandRendered(page, fixture, response, {
        expectBrandElement: fixture === 'branded-full',
      });

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`home--default--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }

  test('home--markdown--canonical', async ({ page }) => {
    const manifest = loadManifest();
    const consoleErrors = collectConsoleErrors(page);

    const response = await gotoAndReady(page, visualUrl(manifest.canonicalHost, '/'));
    await assertBrandRendered(page, 'canonical', response);

    const toggle = page.getByTestId('secret-markdown-toggle');
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', 'true');

    const editor = page.getByTestId('secret-content-input');
    await editor.fill(loadMarkdownSample());
    // Drop the focus ring and show the start of the source, so the shot is
    // the resting editor rather than one scrolled to the caret.
    await editor.blur();
    await editor.evaluate((el) => el.scrollTo(0, 0));

    // The preview renders after a debounce and a lazy import of the
    // renderer; the highlighted code block and the closing blockquote mean
    // the whole sample is in.
    const preview = page.getByTestId('secret-markdown-preview');
    await expect(preview.locator('.hljs-comment')).toBeVisible();
    await expect(preview.locator('blockquote')).toBeVisible();

    expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

    await expect(page).toHaveScreenshot('home--markdown--canonical.png', {
      fullPage: true,
      mask: visualMasks(page),
    });
  });
});
