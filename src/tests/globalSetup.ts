// src/tests/globalSetup.ts

/**
 * Vitest globalSetup: runs once before all test files.
 *
 * Generates the merged locale files in generated/locales/ that
 * i18n tests depend on (key-validation, locale-consistency,
 * naming-convention, security-messages).
 */

import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { resolve } from 'path';

export function setup() {
  // Print test harness banner showing key feature flags
  // Mirrors Ruby harness banners for consistency across test frameworks
  const billingEnabled = process.env.BILLING_ENABLED ?? 'false';
  console.log(`[Vitest] billing:${billingEnabled}`);

  const generatedLocale = resolve(
    process.cwd(),
    'generated/locales/en.json'
  );

  if (!existsSync(generatedLocale)) {
    console.log(
      '[globalSetup] Generating locale files for i18n tests...'
    );
    execSync('pnpm run locales:sync', {
      cwd: process.cwd(),
      stdio: 'pipe',
    });
    console.log('[globalSetup] Locale files generated.');
  }
}
