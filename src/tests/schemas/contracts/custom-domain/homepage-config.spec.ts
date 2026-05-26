// src/tests/schemas/contracts/custom-domain/homepage-config.spec.ts
//
// Contract tests for per-domain homepage config — focused on the
// forward-compat behavior of disabled_homepage_variant.

import { homepageConfigCanonical } from '@/schemas/contracts/custom-domain/homepage-config';
import { describe, expect, it } from 'vitest';

describe('homepageConfigCanonical', () => {
  const basePayload = {
    domain_id: 'd_123',
    enabled: true,
    signup_enabled: true,
    signin_enabled: true,
    created_at: 1700000000,
    updated_at: 1700000000,
  };

  describe('disabled_homepage_variant', () => {
    it('accepts a known variant', () => {
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        disabled_homepage_variant: 'minimal',
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.disabled_homepage_variant).toBe('minimal');
    });

    it('accepts null', () => {
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        disabled_homepage_variant: null,
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.disabled_homepage_variant).toBeNull();
    });

    it('defaults missing field to null', () => {
      const result = homepageConfigCanonical.safeParse(basePayload);
      expect(result.success).toBe(true);
      expect(result.success && result.data.disabled_homepage_variant).toBeNull();
    });

    it('degrades an unknown variant to null instead of failing parse', () => {
      // Forward-compat: a future backend may emit a variant id this
      // frontend doesn't know about. The whole bootstrap payload must
      // still parse — the composable falls back to the frontend default.
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        disabled_homepage_variant: 'future_variant_v99',
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.disabled_homepage_variant).toBeNull();
    });
  });
});
