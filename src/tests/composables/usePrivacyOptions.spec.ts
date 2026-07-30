// src/tests/composables/usePrivacyOptions.spec.ts

/**
 * usePrivacyOptions — duration dropdown contents.
 *
 * The load-bearing behaviour here is the TTL ceiling filter (2026-07-29 API
 * audit, item 4): V2 silently clamps an anonymous secret's TTL to a hard
 * 7-day cap, so the dropdown must not offer durations above it. See
 * apps/api/v2/logic/secrets/base_secret_action.rb#anonymous_max_ttl and
 * WithEntitlements::ANONYMOUS_MAX_TTL.
 *
 * The ceiling itself is the server's to decide — these examples feed it in
 * through the bootstrap payload rather than restating the constant.
 */

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, params?: unknown) =>
      typeof params === 'object' && params !== null && 'count' in params
        ? `${(params as { count: number }).count}:${key}`
        : key,
  }),
}));

import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';

const MINUTE = 60;
const HOUR = 3600;
const DAY = 86400;
const WEEK = 604800;
const TWO_WEEKS = 1209600;
const THIRTY_DAYS = 2592000;

const TTL_OPTIONS = [MINUTE, HOUR, DAY, WEEK, TWO_WEEKS, THIRTY_DAYS];

interface StoreSetup {
  ttl_options?: number[];
  ttl_max_anonymous?: number | null;
  authenticated?: boolean;
  secret_lifetime?: number | null;
  /** Authenticated with no organization at all (server skips the plan limit). */
  withoutOrganization?: boolean;
}

function setupStore(config: StoreSetup = {}) {
  const pinia = createTestingPinia({ createSpy: vi.fn, stubActions: false });
  setActivePinia(pinia);

  const bootstrapStore = useBootstrapStore();
  bootstrapStore.secret_options = {
    default_ttl: WEEK,
    ttl_options: config.ttl_options ?? TTL_OPTIONS,
    ttl_max_anonymous: config.ttl_max_anonymous ?? undefined,
  };
  bootstrapStore.authenticated = config.authenticated ?? false;

  if (config.authenticated && !config.withoutOrganization) {
    bootstrapStore.organization = {
      objid: 'org_obj_1',
      extid: 'onabc123',
      display_name: 'Acme',
      is_default: true,
      limits: {
        teams: 0,
        total_members_per_org: 1,
        custom_domains: 1,
        secret_lifetime: config.secret_lifetime ?? undefined,
      },
    };
  }

  return bootstrapStore;
}

function values() {
  return usePrivacyOptions().lifetimeOptions.value.map((opt) => opt.value);
}

describe('usePrivacyOptions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('lifetimeOptions — anonymous caller', () => {
    // WEEK is the hard cap the server publishes on a stock install.
    it('drops options above the anonymous ceiling the server would clamp to', () => {
      setupStore({ ttl_max_anonymous: WEEK });

      expect(values()).toEqual([MINUTE, HOUR, DAY, WEEK]);
      expect(values()).not.toContain(TWO_WEEKS);
      expect(values()).not.toContain(THIRTY_DAYS);
    });

    it('keeps an option exactly equal to the ceiling', () => {
      setupStore({ ttl_max_anonymous: DAY });

      expect(values()).toEqual([MINUTE, HOUR, DAY]);
    });

    it('honours a ceiling lowered below the cap by PLAN_TTL_ANONYMOUS', () => {
      setupStore({ ttl_max_anonymous: HOUR });

      expect(values()).toEqual([MINUTE, HOUR]);
    });

    // The server always publishes this key now, so an absent one means the
    // payload came from a build that predates the field.
    it('fails open when the payload carries no ceiling at all', () => {
      setupStore({ ttl_max_anonymous: null });

      expect(values()).toEqual(TTL_OPTIONS);
    });

    it('fails open when the ceiling is zero or negative', () => {
      setupStore({ ttl_max_anonymous: 0 });
      expect(values()).toEqual(TTL_OPTIONS);

      setupStore({ ttl_max_anonymous: -1 });
      expect(values()).toEqual(TTL_OPTIONS);
    });
  });

  describe('lifetimeOptions — authenticated caller', () => {
    it("filters by the organization's plan secret_lifetime limit", () => {
      setupStore({
        authenticated: true,
        secret_lifetime: WEEK,
        ttl_max_anonymous: DAY,
      });

      // The anonymous ceiling must not leak onto an authenticated caller.
      expect(values()).toEqual([MINUTE, HOUR, DAY, WEEK]);
    });

    it('treats -1 (unlimited) as no ceiling', () => {
      setupStore({ authenticated: true, secret_lifetime: -1, ttl_max_anonymous: DAY });

      expect(values()).toEqual(TTL_OPTIONS);
    });

    it('fails open when the plan limit is absent from the payload', () => {
      setupStore({ authenticated: true, secret_lifetime: null, ttl_max_anonymous: DAY });

      expect(values()).toEqual(TTL_OPTIONS);
    });

    it('ignores the anonymous ceiling when authenticated without an organization', () => {
      setupStore({ authenticated: true, withoutOrganization: true, ttl_max_anonymous: DAY });

      expect(values()).toEqual(TTL_OPTIONS);
    });
  });

  describe('lifetimeOptions — degenerate configurations', () => {
    it('never returns an empty list: keeps the shortest option below the ceiling', () => {
      setupStore({ ttl_max_anonymous: 30 }); // below every configured option

      expect(values()).toEqual([MINUTE]);
    });

    it('finds the shortest option even when ttl_options is unsorted', () => {
      setupStore({ ttl_options: [DAY, HOUR, WEEK], ttl_max_anonymous: 30 });

      expect(values()).toEqual([HOUR]);
    });

    it('returns an empty list when there are no configured options at all', () => {
      setupStore({ ttl_options: [], ttl_max_anonymous: TWO_WEEKS });

      expect(values()).toEqual([]);
    });

    it('still applies the 30-day global cap', () => {
      setupStore({ ttl_options: [WEEK, THIRTY_DAYS + 1], ttl_max_anonymous: null });

      expect(values()).toEqual([WEEK]);
    });
  });

  describe('consumer contracts', () => {
    /**
     * WorkspaceSecretForm validates localReceiptStore.preferredTtl against
     * this list and falls back to secret_options.default_ttl. A remembered
     * 30-day choice must stop resolving once the ceiling drops below it.
     */
    it('invalidates a remembered over-ceiling preferred TTL, leaving default_ttl valid', () => {
      setupStore({ ttl_max_anonymous: WEEK }); // default_ttl sits exactly at the cap
      const options = values();

      expect(options.includes(THIRTY_DAYS)).toBe(false); // remembered choice
      expect(options.includes(TWO_WEEKS)).toBe(false);
      expect(options.includes(WEEK)).toBe(true); // default_ttl fallback
    });

    /** TtlSelector falls back to lifetimeOptions[0] for an unknown value. */
    it('always leaves TtlSelector a first option to fall back to', () => {
      setupStore({ ttl_max_anonymous: 1 });

      expect(usePrivacyOptions().lifetimeOptions.value[0]).toBeDefined();
    });
  });

  describe('ttlCeiling', () => {
    it('is null for an anonymous caller with no published ceiling', () => {
      setupStore({ ttl_max_anonymous: null });

      expect(usePrivacyOptions().ttlCeiling.value).toBeNull();
    });

    it('is whatever ceiling the server published, for a guest', () => {
      setupStore({ ttl_max_anonymous: WEEK });

      expect(usePrivacyOptions().ttlCeiling.value).toBe(WEEK);
    });

    it('is the plan limit for an authenticated caller', () => {
      setupStore({ authenticated: true, secret_lifetime: WEEK });

      expect(usePrivacyOptions().ttlCeiling.value).toBe(WEEK);
    });
  });

  describe('formatDuration', () => {
    it('formats using the largest whole unit', () => {
      setupStore();
      const { formatDuration } = usePrivacyOptions();

      expect(formatDuration(DAY)).toBe('1:web.UNITS.ttl.duration');
      expect(formatDuration(90)).toBe('1:web.UNITS.ttl.duration');
    });
  });
});
