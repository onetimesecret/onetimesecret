// src/tests/shared/utils/banner-visibility.spec.ts

import { describe, it, expect } from 'vitest';
import {
  bannerAudienceAllows,
  DEFAULT_BANNER_SCOPE,
  type BannerScope,
} from '@/shared/utils/banner-visibility';
import type { BannerAudience } from '@/types/ui/layouts';

/**
 * Global-broadcast visibility matrix. This is the single source of truth for
 * which pages a scoped banner reaches, so it is exercised exhaustively across
 * (scope × audience × domainStrategy). See src/shared/layouts/BaseLayout.vue.
 */
describe('bannerAudienceAllows', () => {
  const audiences: BannerAudience[] = ['public', 'recipient', 'workspace'];
  const nonCustomStrategies = ['canonical', 'subdomain', 'invalid'] as const;

  describe('non-custom domains', () => {
    describe("scope 'all' shows on every audience", () => {
      for (const strategy of nonCustomStrategies) {
        for (const audience of audiences) {
          it(`${strategy} / ${audience}`, () => {
            expect(bannerAudienceAllows('all', audience, strategy)).toBe(true);
          });
        }
      }
    });

    describe("scope 'no_recipient' shows on all but recipient", () => {
      for (const strategy of nonCustomStrategies) {
        it(`${strategy} / public → true`, () => {
          expect(bannerAudienceAllows('no_recipient', 'public', strategy)).toBe(true);
        });
        it(`${strategy} / workspace → true`, () => {
          expect(bannerAudienceAllows('no_recipient', 'workspace', strategy)).toBe(true);
        });
        it(`${strategy} / recipient → false`, () => {
          expect(bannerAudienceAllows('no_recipient', 'recipient', strategy)).toBe(false);
        });
      }
    });

    describe("scope 'workspace' shows only on workspace", () => {
      for (const strategy of nonCustomStrategies) {
        it(`${strategy} / workspace → true`, () => {
          expect(bannerAudienceAllows('workspace', 'workspace', strategy)).toBe(true);
        });
        it(`${strategy} / public → false`, () => {
          expect(bannerAudienceAllows('workspace', 'public', strategy)).toBe(false);
        });
        it(`${strategy} / recipient → false`, () => {
          expect(bannerAudienceAllows('workspace', 'recipient', strategy)).toBe(false);
        });
      }
    });
  });

  describe('custom domains are suppressed unless scope is all', () => {
    for (const audience of audiences) {
      it(`all / ${audience} → true`, () => {
        expect(bannerAudienceAllows('all', audience, 'custom')).toBe(true);
      });
      it(`no_recipient / ${audience} → false`, () => {
        expect(bannerAudienceAllows('no_recipient', audience, 'custom')).toBe(false);
      });
      it(`workspace / ${audience} → false`, () => {
        expect(bannerAudienceAllows('workspace', audience, 'custom')).toBe(false);
      });
    }
  });

  describe('scope fallback', () => {
    it(`null scope behaves as the default (${DEFAULT_BANNER_SCOPE})`, () => {
      // default is no_recipient: public shows, recipient hidden, custom hidden
      expect(bannerAudienceAllows(null, 'public', 'canonical')).toBe(true);
      expect(bannerAudienceAllows(null, 'recipient', 'canonical')).toBe(false);
      expect(bannerAudienceAllows(null, 'public', 'custom')).toBe(false);
    });

    it('undefined scope behaves as the default', () => {
      expect(bannerAudienceAllows(undefined, 'workspace', 'subdomain')).toBe(true);
      expect(bannerAudienceAllows(undefined, 'recipient', 'subdomain')).toBe(false);
    });

    it('DEFAULT_BANNER_SCOPE is no_recipient (matches backend)', () => {
      const expected: BannerScope = 'no_recipient';
      expect(DEFAULT_BANNER_SCOPE).toBe(expected);
    });
  });
});
