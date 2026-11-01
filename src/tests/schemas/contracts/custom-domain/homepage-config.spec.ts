// src/tests/schemas/contracts/custom-domain/homepage-config.spec.ts
//
// Contract tests for per-domain homepage config — focused on the
// forward-compat behavior of disabled_homepage_variant and secrets_mode.

import { homepageConfigCanonical } from '@/schemas/contracts/custom-domain/homepage-config';
import { homepageConfigResponseSchema } from '@/schemas/api/domains/responses/homepage-config';
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

  describe('signup_enabled / signin_enabled defaults', () => {
    // Both auth-link toggles default OFF: a payload that omits them parses to
    // false so the homepage nav links stay hidden unless a domain opts in.
    const payloadWithoutFlags = {
      domain_id: 'd_123',
      enabled: true,
      created_at: 1700000000,
      updated_at: 1700000000,
    };

    it('defaults signup_enabled to false when omitted', () => {
      const result = homepageConfigCanonical.safeParse(payloadWithoutFlags);
      expect(result.success).toBe(true);
      expect(result.success && result.data.signup_enabled).toBe(false);
    });

    it('defaults signin_enabled to false when omitted', () => {
      const result = homepageConfigCanonical.safeParse(payloadWithoutFlags);
      expect(result.success).toBe(true);
      expect(result.success && result.data.signin_enabled).toBe(false);
    });

    it('honours an explicit true opt-in', () => {
      const result = homepageConfigCanonical.safeParse({
        ...payloadWithoutFlags,
        signup_enabled: true,
        signin_enabled: true,
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.signup_enabled).toBe(true);
      expect(result.success && result.data.signin_enabled).toBe(true);
    });
  });

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

  describe('secrets_mode', () => {
    it('accepts create', () => {
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        secrets_mode: 'create',
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.secrets_mode).toBe('create');
    });

    it('accepts incoming', () => {
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        secrets_mode: 'incoming',
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.secrets_mode).toBe('incoming');
    });

    it('defaults a missing field to create (payloads from older backends)', () => {
      const result = homepageConfigCanonical.safeParse(basePayload);
      expect(result.success).toBe(true);
      expect(result.success && result.data.secrets_mode).toBe('create');
    });

    it('degrades an unknown mode to create instead of failing parse', () => {
      // Forward-compat: a future backend may emit a mode this frontend
      // doesn't know about. Degrading to the historical create behavior
      // (whose API gate independently blocks anonymous creation on
      // incoming-mode domains) beats crashing the bootstrap parse.
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        secrets_mode: 'future_mode_v99',
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.secrets_mode).toBe('create');
    });

    it('round-trips through the PUT /homepage-config response envelope', () => {
      // domainsStore.putHomepageConfig $patches bootstrapStore with the PUT
      // response record; if the response schema dropped secrets_mode, every
      // save would silently rewrite the client-side mode to 'create'.
      const result = homepageConfigResponseSchema.safeParse({
        user_id: 'u_123',
        record: {
          ...basePayload,
          secrets_mode: 'incoming',
        },
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.record?.secrets_mode).toBe('incoming');
    });
  });

  describe('allowed_cidrs / denied_cidrs (homepage network rules)', () => {
    it('defaults both lists to [] when omitted (payloads from older backends)', () => {
      // No rules = no restriction; the editor must render empty lists, not
      // crash on undefined, for a backend that pre-dates the fields.
      const result = homepageConfigCanonical.safeParse(basePayload);
      expect(result.success).toBe(true);
      expect(result.success && result.data.allowed_cidrs).toEqual([]);
      expect(result.success && result.data.denied_cidrs).toEqual([]);
    });

    it('carries normalized CIDR entries through', () => {
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        allowed_cidrs: ['203.0.113.0/24', '2001:db8::/32'],
        denied_cidrs: ['203.0.113.7/32'],
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.allowed_cidrs).toEqual([
        '203.0.113.0/24',
        '2001:db8::/32',
      ]);
      expect(result.success && result.data.denied_cidrs).toEqual(['203.0.113.7/32']);
    });

    it('rejects a non-array value instead of coercing it', () => {
      // A bare string must not silently become a one-entry list: the
      // backend contract is Array<String> and the editor spreads the array.
      const result = homepageConfigCanonical.safeParse({
        ...basePayload,
        allowed_cidrs: '203.0.113.0/24',
      });
      expect(result.success).toBe(false);
    });

    it('round-trips through the PUT /homepage-config response envelope', () => {
      // After a save the editor re-seeds from the response record, so the
      // response schema must keep the lists (normalized by the server).
      const result = homepageConfigResponseSchema.safeParse({
        user_id: 'u_123',
        record: {
          ...basePayload,
          allowed_cidrs: ['10.0.0.0/8'],
          denied_cidrs: [],
        },
      });
      expect(result.success).toBe(true);
      expect(result.success && result.data.record?.allowed_cidrs).toEqual(['10.0.0.0/8']);
      expect(result.success && result.data.record?.denied_cidrs).toEqual([]);
    });
  });
});
