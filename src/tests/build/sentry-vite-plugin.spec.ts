// src/tests/build/sentry-vite-plugin.spec.ts

/**
 * Tests for Sentry Vite Plugin Configuration
 *
 * Issue: #2959 - Upload source maps to Sentry for readable stacktraces
 *
 * These tests verify the build configuration for Sentry source map uploads:
 * - Environment variable documentation is complete
 * - No credentials are hardcoded in config files
 * - Plugin configuration follows graceful degradation pattern
 *
 * Run:
 *   pnpm test src/tests/build/sentry-vite-plugin.spec.ts
 */

import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const PROJECT_ROOT = path.resolve(process.cwd());

describe('Sentry Vite Plugin Configuration', () => {
  describe('Environment Variable Documentation', () => {
    const envReferencePath = path.join(PROJECT_ROOT, '.env.reference');

    it('documents SENTRY_AUTH_TOKEN in .env.reference', () => {
      const content = fs.readFileSync(envReferencePath, 'utf-8');
      expect(content).toContain('SENTRY_AUTH_TOKEN');
    });

    it('documents SENTRY_ORG in .env.reference', () => {
      const content = fs.readFileSync(envReferencePath, 'utf-8');
      expect(content).toContain('SENTRY_ORG');
    });

    it('documents SENTRY_PROJECT in .env.reference', () => {
      const content = fs.readFileSync(envReferencePath, 'utf-8');
      expect(content).toContain('SENTRY_PROJECT');
    });

    it('documents SENTRY_URL in .env.reference (for self-hosted)', () => {
      const content = fs.readFileSync(envReferencePath, 'utf-8');
      expect(content).toContain('SENTRY_URL');
    });

    it('documents SENTRY_RELEASE in .env.reference', () => {
      const content = fs.readFileSync(envReferencePath, 'utf-8');
      expect(content).toContain('SENTRY_RELEASE');
    });

    it('marks SENTRY_AUTH_TOKEN as CI-only usage', () => {
      const content = fs.readFileSync(envReferencePath, 'utf-8');
      // Verify the comment indicates CI-only usage
      const index = content.indexOf('SENTRY_AUTH_TOKEN');
      const authTokenSection = content.substring(Math.max(0, index - 150), index + 50);
      expect(
        authTokenSection.includes('CI only') || authTokenSection.includes('CI/CD') || authTokenSection.includes('@sentry/vite-plugin')
      ).toBe(true);
    });
  });

  describe('Security: No Hardcoded Credentials', () => {
    const viteConfigPath = path.join(PROJECT_ROOT, 'vite.config.ts');

    it('vite.config.ts does not contain hardcoded auth tokens', () => {
      const content = fs.readFileSync(viteConfigPath, 'utf-8');

      // Check for patterns that might indicate hardcoded tokens
      // Sentry auth tokens start with 'sntrys_' or similar patterns
      expect(content).not.toMatch(/sntrys_[a-zA-Z0-9]+/);
      expect(content).not.toMatch(/authToken:\s*['"][^'"]+['"]/);
      expect(content).not.toMatch(/SENTRY_AUTH_TOKEN\s*=\s*['"][^'"]+['"]/);
    });

    // Note: org and project have fallback defaults ('onetimesecret', 'frontend')
    // which is acceptable since they are non-sensitive configuration values.
    // Only authToken is a secret that must never be hardcoded.
  });

  describe('Vite Config Structure', () => {
    const viteConfigPath = path.join(PROJECT_ROOT, 'vite.config.ts');

    it('has sourcemap enabled in build config', () => {
      const content = fs.readFileSync(viteConfigPath, 'utf-8');
      // The build config should have sourcemap: true for Sentry to work
      expect(content).toMatch(/sourcemap:\s*true/);
    });

    it('documents CI-based sourcemap upload (not build-time)', () => {
      const content = fs.readFileSync(viteConfigPath, 'utf-8');
      // Sourcemaps are uploaded via sentry-cli in CI, not via sentryVitePlugin at build time.
      // This keeps auth tokens out of the build context.
      expect(content).toContain('Sentry sourcemaps are uploaded via CI');
    });
  });

  describe('Build Output Configuration', () => {
    const viteConfigPath = path.join(PROJECT_ROOT, 'vite.config.ts');

    it('outputs to public/web/dist directory', () => {
      const content = fs.readFileSync(viteConfigPath, 'utf-8');
      expect(content).toContain("outDir: '../public/web/dist'");
    });

    it('generates manifest for asset tracking', () => {
      const content = fs.readFileSync(viteConfigPath, 'utf-8');
      expect(content).toMatch(/manifest:\s*true/);
    });
  });
});

describe('Sentry Plugin Behavior Specification', () => {
  /**
   * These are specification tests that document expected behavior.
   * They pass based on configuration analysis, not runtime verification.
   * Actual build verification requires running `pnpm build` with/without env vars.
   */

  describe('Graceful Degradation', () => {
    // Plugin should be conditionally activated based on SENTRY_AUTH_TOKEN
    // Expected pattern: process.env.SENTRY_AUTH_TOKEN ? sentryVitePlugin({...}) : null
    // Plugin array should filter out null/undefined using .filter(Boolean)
    it.todo('plugin should be conditionally activated based on SENTRY_AUTH_TOKEN');

    // Expected behavior: build completes without error
    // Source maps are generated locally but not uploaded
    // No console errors about missing Sentry configuration
    it.todo('production build should succeed when SENTRY_AUTH_TOKEN is NOT set');

    // Expected behavior: build completes and uploads source maps
    // Console shows upload progress/success
    // Sentry dashboard shows source maps for the release
    it.todo('production build should upload source maps when SENTRY_AUTH_TOKEN IS set');

    // Expected behavior: dev server starts normally
    // No Sentry upload attempts regardless of env vars
    // Plugin should check NODE_ENV or Vite's mode
    it.todo('development build should NOT attempt source map upload');
  });

  describe('Source Map Generation', () => {
    // Expected output: public/web/dist/assets/*.js.map
    // The pattern follows rolldownOptions.output.entryFileNames
    it.todo('source maps should be generated in assets directory');

    // Source maps should be:
    // - Generated for Sentry upload
    // - Either deleted after upload OR not served to users
    // - sentryVitePlugin has sourcemaps.filesToDeleteAfterUpload option
    it.todo('source maps should not be included in production bundle');
  });
});
