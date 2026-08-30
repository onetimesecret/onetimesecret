// src/tests/composables/useDomainStatus.spec.ts

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref, nextTick } from 'vue';
import { useDomainStatus } from '@/shared/composables/useDomainStatus';
import type { CustomDomain } from '@/schemas/shapes/v3';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.STATUS.active': 'Active',
        'web.STATUS.inactive': 'Inactive',
        'web.STATUS.dns_incorrect': 'DNS Incorrect',
        'web.STATUS.unverified': 'Unverified',
      };
      return translations[key] ?? key;
    },
  }),
}));

describe('useDomainStatus', () => {
  // CustomDomain (V3 shape) carries parsed values, not wire primitives:
  // created/updated and vhost.last_monitored_unix are Date, not epoch numbers.
  const MOCK_DATE = new Date(1700000000000);

  // Built as a fully-typed base object (no spread) so TS checks it directly
  // against CustomDomain; merging `overrides` on a separately-typed variable
  // avoids a spurious TS2719 "unrelated types" error that vue-tsc raises when
  // an inline object literal spreads Partial<CustomDomain> directly into a
  // return position typed as CustomDomain.
  const createMockDomain = (overrides: Partial<CustomDomain> = {}): CustomDomain => {
    const base: CustomDomain = {
      domainid: 'domain-uuid-123',
      extid: 'domain-123',
      custid: 'cust-456',
      display_domain: 'example.com',
      base_domain: 'example.com',
      subdomain: '',
      trd: '',
      tld: 'com',
      sld: 'example',
      is_apex: true,
      txt_validation_host: '_onetime-challenge.example.com',
      txt_validation_value: 'validation-value-abc123',
      verified: true,
      resolving: true,
      status: 'pending',
      brand: null,
      created: MOCK_DATE,
      updated: MOCK_DATE,
      vhost: {
        status: 'PENDING',
      },
      vhost_fetch_failed_at: null,
    };
    return { ...base, ...overrides };
  };

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset Date.now mock if any
    vi.useRealTimers();
  });

  describe('isActive', () => {
    it('returns true for ACTIVE status', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE } }));
      const { isActive } = useDomainStatus(domain);
      expect(isActive.value).toBe(true);
    });

    it('returns true for ACTIVE_SSL status', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'ACTIVE_SSL', last_monitored_unix: MOCK_DATE } }));
      const { isActive } = useDomainStatus(domain);
      expect(isActive.value).toBe(true);
    });

    it('returns true for ACTIVE_SSL_PROXIED status', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'ACTIVE_SSL_PROXIED', last_monitored_unix: MOCK_DATE } }));
      const { isActive } = useDomainStatus(domain);
      expect(isActive.value).toBe(true);
    });

    it('returns false for PENDING status', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'PENDING' } }));
      const { isActive } = useDomainStatus(domain);
      expect(isActive.value).toBe(false);
    });

    it('returns false for null domain', () => {
      const domain = ref<CustomDomain | null>(null);
      const { isActive } = useDomainStatus(domain);
      expect(isActive.value).toBe(false);
    });
  });

  describe('isWarning', () => {
    it('returns true for DNS_INCORRECT status', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'DNS_INCORRECT' } }));
      const { isWarning } = useDomainStatus(domain);
      expect(isWarning.value).toBe(true);
    });

    it('returns false for other statuses', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE } }));
      const { isWarning } = useDomainStatus(domain);
      expect(isWarning.value).toBe(false);
    });
  });

  describe('isError', () => {
    it('returns true when domain exists but is neither active nor warning', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'PENDING' } }));
      const { isError } = useDomainStatus(domain);
      expect(isError.value).toBe(true);
    });

    it('returns false when domain is active', () => {
      const domain = ref(createMockDomain({ vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE } }));
      const { isError } = useDomainStatus(domain);
      expect(isError.value).toBe(false);
    });

    it('returns false when domain is null', () => {
      const domain = ref<CustomDomain | null>(null);
      const { isError } = useDomainStatus(domain);
      expect(isError.value).toBe(false);
    });
  });

  describe('isStale', () => {
    const STALE_WINDOW_SECONDS = 6 * 60 * 60; // 6 hours

    it('returns false when vhost_fetch_failed_at is null', () => {
      const domain = ref(createMockDomain({ vhost_fetch_failed_at: null }));
      const { isStale } = useDomainStatus(domain);
      expect(isStale.value).toBe(false);
    });

    it('returns true when failure is within stale window', () => {
      const now = Date.now() / 1000;
      const recentFailure = now - 60; // 1 minute ago
      const domain = ref(createMockDomain({ vhost_fetch_failed_at: recentFailure }));
      const { isStale } = useDomainStatus(domain);
      expect(isStale.value).toBe(true);
    });

    it('returns false when failure is older than stale window', () => {
      const now = Date.now() / 1000;
      const oldFailure = now - STALE_WINDOW_SECONDS - 1; // Just past window
      const domain = ref(createMockDomain({ vhost_fetch_failed_at: oldFailure }));
      const { isStale } = useDomainStatus(domain);
      expect(isStale.value).toBe(false);
    });

    it('returns false when failure timestamp is in the future', () => {
      const now = Date.now() / 1000;
      const futureFailure = now + 3600; // 1 hour in future
      const domain = ref(createMockDomain({ vhost_fetch_failed_at: futureFailure }));
      const { isStale } = useDomainStatus(domain);
      expect(isStale.value).toBe(false);
    });
  });

  describe('displayStatus', () => {
    it('returns empty string for null domain', () => {
      const domain = ref<CustomDomain | null>(null);
      const { displayStatus } = useDomainStatus(domain);
      expect(displayStatus.value).toBe('');
    });

    it('returns "Unverified" when stale', () => {
      const now = Date.now() / 1000;
      const domain = ref(createMockDomain({
        vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE },
        vhost_fetch_failed_at: now - 60,
      }));
      const { displayStatus } = useDomainStatus(domain);
      expect(displayStatus.value).toBe('Unverified');
    });

    it('returns "Active" for active domain', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE },
        vhost_fetch_failed_at: null,
      }));
      const { displayStatus } = useDomainStatus(domain);
      expect(displayStatus.value).toBe('Active');
    });

    it('returns "DNS Incorrect" for warning status', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'DNS_INCORRECT' },
        vhost_fetch_failed_at: null,
      }));
      const { displayStatus } = useDomainStatus(domain);
      expect(displayStatus.value).toBe('DNS Incorrect');
    });

    it('returns "Inactive" for error status', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'PENDING' },
        vhost_fetch_failed_at: null,
      }));
      const { displayStatus } = useDomainStatus(domain);
      expect(displayStatus.value).toBe('Inactive');
    });
  });

  describe('statusIcon', () => {
    it('returns help-circle for stale domain', () => {
      const now = Date.now() / 1000;
      const domain = ref(createMockDomain({ vhost_fetch_failed_at: now - 60 }));
      const { statusIcon } = useDomainStatus(domain);
      expect(statusIcon.value).toBe('help-circle');
    });

    it('returns check-circle for active domain', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE },
        vhost_fetch_failed_at: null,
      }));
      const { statusIcon } = useDomainStatus(domain);
      expect(statusIcon.value).toBe('check-circle');
    });

    it('returns alert-circle for warning status', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'DNS_INCORRECT' },
        vhost_fetch_failed_at: null,
      }));
      const { statusIcon } = useDomainStatus(domain);
      expect(statusIcon.value).toBe('alert-circle');
    });

    it('returns close-circle for error status', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'PENDING' },
        vhost_fetch_failed_at: null,
      }));
      const { statusIcon } = useDomainStatus(domain);
      expect(statusIcon.value).toBe('close-circle');
    });
  });

  describe('statusColor', () => {
    it('returns amber classes for stale domain', () => {
      const now = Date.now() / 1000;
      const domain = ref(createMockDomain({ vhost_fetch_failed_at: now - 60 }));
      const { statusColor } = useDomainStatus(domain);
      expect(statusColor.value).toBe('text-amber-500 dark:text-amber-400');
    });

    it('returns emerald classes for active domain', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE },
        vhost_fetch_failed_at: null,
      }));
      const { statusColor } = useDomainStatus(domain);
      expect(statusColor.value).toBe('text-emerald-600 dark:text-emerald-400');
    });

    it('returns amber classes for warning status', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'DNS_INCORRECT' },
        vhost_fetch_failed_at: null,
      }));
      const { statusColor } = useDomainStatus(domain);
      expect(statusColor.value).toBe('text-amber-500 dark:text-amber-400');
    });

    it('returns rose classes for error status', () => {
      const domain = ref(createMockDomain({
        vhost: { status: 'PENDING' },
        vhost_fetch_failed_at: null,
      }));
      const { statusColor } = useDomainStatus(domain);
      expect(statusColor.value).toBe('text-rose-600 dark:text-rose-500');
    });
  });

  describe('reactivity', () => {
    it('updates computed values when domain changes', async () => {
      const domain = ref<CustomDomain | null>(createMockDomain({
        vhost: { status: 'PENDING' },
      }));
      const { isActive, displayStatus, statusColor } = useDomainStatus(domain);

      expect(isActive.value).toBe(false);
      expect(displayStatus.value).toBe('Inactive');
      expect(statusColor.value).toBe('text-rose-600 dark:text-rose-500');

      // Update domain status
      domain.value = createMockDomain({
        vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE },
      });
      await nextTick();

      expect(isActive.value).toBe(true);
      expect(displayStatus.value).toBe('Active');
      expect(statusColor.value).toBe('text-emerald-600 dark:text-emerald-400');
    });

    it('handles domain becoming null', async () => {
      const domain = ref<CustomDomain | null>(createMockDomain({
        vhost: { status: 'ACTIVE', last_monitored_unix: MOCK_DATE },
      }));
      const { isActive, displayStatus, isError } = useDomainStatus(domain);

      expect(isActive.value).toBe(true);

      domain.value = null;
      await nextTick();

      expect(isActive.value).toBe(false);
      expect(displayStatus.value).toBe('');
      expect(isError.value).toBe(false);
    });
  });
});
