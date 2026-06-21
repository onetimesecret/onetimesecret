// src/tests/apps/workspace/components/domains/DomainEmailDnsRecords.spec.ts
//
// Tests for DomainEmailDnsRecords.vue covering:
// 1. DNS records card rendering with type, name, value
// 2. Per-record status indicators with correct colors
// 3. Validate event emission on re-validate button click
// 4. Validation status banner (verified/pending/failed)
// 5. Empty state when no records
// 6. Last validated timestamp display

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import DomainEmailDnsRecords from '@/apps/workspace/components/domains/DomainEmailDnsRecords.vue';
import type { EmailDnsRecord, EmailValidationStatus } from '@/schemas/contracts/email-config';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" :class="$attrs.class" />',
    props: ['collection', 'name'],
  },
}));

vi.mock('@/shared/composables/useClipboard', () => ({
  useClipboard: () => ({
    copyToClipboard: vi.fn().mockResolvedValue(true),
  }),
}));

// ─────────────────────────────────────────────────────────────────────────────
// i18n setup
// ─────────────────────────────────────────────────────────────────────────────

const i18n = createTestI18n();

// ─────────────────────────────────────────────────────────────────────────────
// Test Fixtures
// ─────────────────────────────────────────────────────────────────────────────

const mockDnsRecords: EmailDnsRecord[] = [
  { type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none', status: 'verified' },
  { type: 'CNAME', name: 'em._domainkey.example.com', value: 'dkim.sendgrid.net', status: 'pending' },
  { type: 'TXT', name: 'example.com', value: 'v=spf1 include:sendgrid.net ~all', status: 'failed' },
];

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('DomainEmailDnsRecords', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createTestingPinia>;

  beforeEach(() => {
    pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (props: Partial<{
    dnsRecords: EmailDnsRecord[];
    validationStatus: EmailValidationStatus;
    lastValidatedAt: Date | null;
    dnsCheckCompletedAt: Date | null;
    providerCheckCompletedAt: Date | null;
    lastError: string | null;
    isValidating: boolean;
  }> = {}) => mount(DomainEmailDnsRecords, {
      props: {
        dnsRecords: props.dnsRecords ?? mockDnsRecords,
        validationStatus: props.validationStatus ?? 'pending',
        lastValidatedAt: props.lastValidatedAt ?? null,
        dnsCheckCompletedAt: props.dnsCheckCompletedAt ?? null,
        providerCheckCompletedAt: props.providerCheckCompletedAt ?? null,
        lastError: props.lastError ?? null,
        isValidating: props.isValidating ?? false,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });

  // ─────────────────────────────────────────────────────────────────────────
  // DNS records cards
  // ─────────────────────────────────────────────────────────────────────────

  describe('DNS records cards', () => {
    it('renders cards when records are present', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards).toHaveLength(3);
    });

    it('renders one card per DNS record', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards).toHaveLength(3);
    });

    it('displays record type in each card', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards[0].text()).toContain('TXT');
      expect(cards[1].text()).toContain('CNAME');
      expect(cards[2].text()).toContain('TXT');
    });

    it('displays record name in each card', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards[0].text()).toContain('_dmarc.example.com');
      expect(cards[1].text()).toContain('em._domainkey.example.com');
    });

    it('displays record value in each card', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards[0].text()).toContain('v=DMARC1; p=none');
      expect(cards[1].text()).toContain('dkim.sendgrid.net');
    });

    it('shows Name and Value labels in each card', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards[0].text()).toContain('web.domains.email.dns_column_name');
      expect(cards[0].text()).toContain('web.domains.email.dns_column_value');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Per-record status indicators
  // ─────────────────────────────────────────────────────────────────────────

  describe('Per-record dual indicators (DNS + Resolving)', () => {
    it('shows DNS and Resolving labels in each card', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards[0].text()).toContain('web.domains.email.dns_check_label');
      expect(cards[0].text()).toContain('web.domains.email.provider_check_label');
    });

    it('applies emerald to DNS indicator when dns_exists is true', () => {
      const records: EmailDnsRecord[] = [
        { type: 'TXT', name: 'example.com', value: 'v=spf1', status: 'verified', dns_exists: true, value_matches: true },
      ];
      wrapper = mountComponent({ dnsRecords: records });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const indicators = cards[0].findAll('.inline-flex.items-center.gap-1');
      const dnsIndicator = indicators.find((i) => i.text().includes('dns_check_label'));
      expect(dnsIndicator!.classes()).toContain('text-emerald-600');
    });

    it('applies gray to DNS indicator when dns_exists is not true', () => {
      const records: EmailDnsRecord[] = [
        { type: 'TXT', name: 'example.com', value: 'v=spf1', status: 'pending', dns_exists: null },
      ];
      wrapper = mountComponent({ dnsRecords: records });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const indicators = cards[0].findAll('.inline-flex.items-center.gap-1');
      const dnsIndicator = indicators.find((i) => i.text().includes('dns_check_label'));
      expect(dnsIndicator!.classes()).toContain('text-gray-300');
    });

    it('applies emerald to Provider indicator when validationStatus is verified and no per-record data', () => {
      // Fallback: no provider_verified on records -> falls back to domain-level effectiveStatus
      wrapper = mountComponent({
        validationStatus: 'verified',
        dnsCheckCompletedAt: new Date(),
        providerCheckCompletedAt: new Date(),
      });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const indicators = cards[0].findAll('.inline-flex.items-center.gap-1');
      const resolvingIndicator = indicators.find((i) => i.text().includes('provider_check_label'));
      expect(resolvingIndicator!.classes()).toContain('text-emerald-600');
    });

    it('applies emerald to Provider indicator when record.provider_verified is true', () => {
      const records: EmailDnsRecord[] = [
        { type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none', status: 'verified', provider_verified: true },
      ];
      wrapper = mountComponent({ dnsRecords: records, validationStatus: 'failed' });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const indicators = cards[0].findAll('.inline-flex.items-center.gap-1');
      const resolvingIndicator = indicators.find((i) => i.text().includes('provider_check_label'));
      expect(resolvingIndicator!.classes()).toContain('text-emerald-600');
    });

    it('applies gray to Provider indicator when record.provider_verified is false even if domain is verified', () => {
      const records: EmailDnsRecord[] = [
        { type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none', status: 'failed', provider_verified: false },
      ];
      wrapper = mountComponent({
        dnsRecords: records,
        validationStatus: 'verified',
        dnsCheckCompletedAt: new Date(),
        providerCheckCompletedAt: new Date(),
      });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const indicators = cards[0].findAll('.inline-flex.items-center.gap-1');
      const resolvingIndicator = indicators.find((i) => i.text().includes('provider_check_label'));
      expect(resolvingIndicator!.classes()).toContain('text-gray-300');
    });

    it('applies gray to Provider indicator when validationStatus is not verified and no per-record data', () => {
      wrapper = mountComponent({ validationStatus: 'pending' });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const indicators = cards[0].findAll('.inline-flex.items-center.gap-1');
      const resolvingIndicator = indicators.find((i) => i.text().includes('provider_check_label'));
      expect(resolvingIndicator!.classes()).toContain('text-gray-300');
    });

    it('uses check-circle-solid icon for both indicators', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const dualContainer = cards[0].find('.inline-flex.items-center.gap-3');
      const icons = dualContainer.findAll('.o-icon');
      icons.forEach((icon) => {
        expect(icon.attributes('data-icon-name')).toBe('check-circle-solid');
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Validate event
  // ─────────────────────────────────────────────────────────────────────────

  describe('Validate event', () => {
    it('emits validate event when re-validate button is clicked', async () => {
      wrapper = mountComponent();

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('web.domains.email.revalidate'));
      expect(revalidateButton).toBeDefined();

      await revalidateButton!.trigger('click');

      expect(wrapper.emitted('validate')).toBeTruthy();
      expect(wrapper.emitted('validate')).toHaveLength(1);
    });

    it('disables re-validate button when isValidating is true', () => {
      wrapper = mountComponent({ isValidating: true });

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('web.domains.email.validating'));
      expect(revalidateButton).toBeDefined();
      expect(revalidateButton!.attributes('disabled')).toBeDefined();
    });

    it('shows "Validating..." text when isValidating is true', () => {
      wrapper = mountComponent({ isValidating: true });

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('web.domains.email.validating'));
      expect(revalidateButton).toBeDefined();
    });

    it('shows "Re-validate" text when not validating', () => {
      wrapper = mountComponent({ isValidating: false });

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('web.domains.email.revalidate'));
      expect(revalidateButton).toBeDefined();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Validation status banner
  // ─────────────────────────────────────────────────────────────────────────

  describe('Validation status banner', () => {
    const completedTimestamps = {
      dnsCheckCompletedAt: new Date('2025-06-15T14:00:00Z'),
      providerCheckCompletedAt: new Date('2025-06-15T14:30:00Z'),
    };

    it('shows verified banner when status is verified and both checks complete', () => {
      wrapper = mountComponent({ validationStatus: 'verified', ...completedTimestamps });

      const banner = wrapper.find('[role="status"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('web.domains.email.domain_verified');
    });

    it('shows failed banner when status is failed and both checks complete', () => {
      wrapper = mountComponent({ validationStatus: 'failed', ...completedTimestamps });

      const banner = wrapper.find('[role="alert"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('web.domains.email.validation_failed');
    });

    it('shows error message in failed banner when lastError is present', () => {
      wrapper = mountComponent({
        validationStatus: 'failed',
        lastError: 'Provider status: not_found',
        ...completedTimestamps,
      });

      const banner = wrapper.find('[role="alert"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('Provider status: not_found');
    });

    it('shows pending banner when status is pending', () => {
      wrapper = mountComponent({ validationStatus: 'pending' });

      const banners = wrapper.findAll('[role="status"]');
      const pendingBanner = banners.find((b) => b.text().includes('web.domains.email.status_pending'));
      expect(pendingBanner).toBeDefined();
    });

    it('shows pending banner when status is verified but checks incomplete', () => {
      wrapper = mountComponent({
        validationStatus: 'verified',
        dnsCheckCompletedAt: new Date(),
        providerCheckCompletedAt: null,
      });

      const banners = wrapper.findAll('[role="status"]');
      const pendingBanner = banners.find((b) => b.text().includes('web.domains.email.status_pending'));
      expect(pendingBanner).toBeDefined();
    });

    it('shows pending banner when isValidating is true regardless of status', () => {
      wrapper = mountComponent({
        validationStatus: 'verified',
        isValidating: true,
        ...completedTimestamps,
      });

      const banners = wrapper.findAll('[role="status"]');
      const pendingBanner = banners.find((b) => b.text().includes('web.domains.email.status_pending'));
      expect(pendingBanner).toBeDefined();
    });

    it('shows last validated timestamp in verified banner', () => {
      const lastValidated = new Date('2025-06-15T14:30:00Z');
      wrapper = mountComponent({
        validationStatus: 'verified',
        lastValidatedAt: lastValidated,
        ...completedTimestamps,
      });

      const banner = wrapper.find('[role="status"]');
      expect(banner.text()).toContain('web.domains.email.last_validated');
    });

    it('shows last validated timestamp in failed banner', () => {
      const lastValidated = new Date('2025-06-15T14:30:00Z');
      wrapper = mountComponent({
        validationStatus: 'failed',
        lastValidatedAt: lastValidated,
        ...completedTimestamps,
      });

      const banner = wrapper.find('[role="alert"]');
      expect(banner.text()).toContain('web.domains.email.last_validated');
    });

    it('does not show timestamp when lastValidatedAt is null', () => {
      wrapper = mountComponent({
        validationStatus: 'verified',
        lastValidatedAt: null,
        ...completedTimestamps,
      });

      const banner = wrapper.find('[role="status"]');
      expect(banner.text()).not.toContain('web.domains.email.last_validated');
    });

    it('uses emerald background for verified banner', () => {
      wrapper = mountComponent({ validationStatus: 'verified', ...completedTimestamps });

      const banner = wrapper.find('[role="status"]');
      expect(banner.classes()).toContain('bg-emerald-50');
    });

    it('uses rose background for failed banner', () => {
      wrapper = mountComponent({ validationStatus: 'failed', ...completedTimestamps });

      const banner = wrapper.find('[role="alert"]');
      expect(banner.classes()).toContain('bg-rose-50');
    });

    it('uses amber background for pending banner', () => {
      wrapper = mountComponent({ validationStatus: 'pending' });

      const banners = wrapper.findAll('[role="status"]');
      const pendingBanner = banners.find((b) => b.classes().includes('bg-amber-50'));
      expect(pendingBanner).toBeDefined();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Optional / advisory records (DMARC)
  // ─────────────────────────────────────────────────────────────────────────

  describe('Optional / advisory records', () => {
    const optionalRecords: EmailDnsRecord[] = [
      { type: 'CNAME', name: 'abc._domainkey.example.com', value: 'abc.dkim.amazonses.com', status: 'pending' },
      { type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none;', status: 'pending', optional: true },
    ];

    it('shows Recommended badge on optional records', () => {
      wrapper = mountComponent({ dnsRecords: optionalRecords });

      const badges = wrapper.findAll('[data-testid="dns-record-optional-badge"]');
      expect(badges).toHaveLength(1);
      expect(badges[0].text()).toContain('web.domains.email.dns_optional_label');
    });

    it('does not show Recommended badge on required records', () => {
      wrapper = mountComponent({ dnsRecords: optionalRecords });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      const firstCard = cards[0];
      expect(firstCard.find('[data-testid="dns-record-optional-badge"]').exists()).toBe(false);
    });

    it('shows advisory hint text on optional records', () => {
      wrapper = mountComponent({ dnsRecords: optionalRecords });

      const hints = wrapper.findAll('[data-testid="dns-record-optional-hint"]');
      expect(hints).toHaveLength(1);
      expect(hints[0].text()).toContain('web.domains.email.dns_optional_hint');
    });

    it('applies dashed border styling to optional records', () => {
      wrapper = mountComponent({ dnsRecords: optionalRecords });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards[1].classes()).toContain('border-dashed');
      expect(cards[0].classes()).not.toContain('border-dashed');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────

  describe('Empty state', () => {
    it('shows empty state when no DNS records', () => {
      wrapper = mountComponent({ dnsRecords: [] });

      const cards = wrapper.findAll('[data-testid="dns-record-card"]');
      expect(cards).toHaveLength(0);

      // Should show the dashed border empty state
      const emptyState = wrapper.find('.border-dashed');
      expect(emptyState.exists()).toBe(true);
    });

    it('shows description text in empty state', () => {
      wrapper = mountComponent({ dnsRecords: [] });

      const emptyState = wrapper.find('.border-dashed');
      expect(emptyState.text()).toContain('web.domains.email.dns_records_description');
    });

    it('does not show cards when records list is empty', () => {
      wrapper = mountComponent({ dnsRecords: [] });

      expect(wrapper.findAll('[data-testid="dns-record-card"]')).toHaveLength(0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Section heading and accessibility
  // ─────────────────────────────────────────────────────────────────────────

  describe('Section heading and accessibility', () => {
    it('has a section heading with correct id', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('#dns-records-heading');
      expect(heading.exists()).toBe(true);
      expect(heading.text()).toBe('web.domains.email.dns_records_title');
    });

    it('section is labelled by heading', () => {
      wrapper = mountComponent();

      const section = wrapper.find('section');
      expect(section.attributes('aria-labelledby')).toBe('dns-records-heading');
    });

    it('copy buttons have accessible aria-labels', () => {
      wrapper = mountComponent();

      const copyButtons = wrapper.findAll('button[aria-label]');
      // Each record has 2 copy buttons (name + value), so 3 records = 6 buttons
      // (plus the re-validate button which doesn't have an aria-label attribute in same format)
      const filteredButtons = copyButtons.filter((b) =>
        b.attributes('aria-label')?.includes('web.domains.email.copy')
      );
      expect(filteredButtons.length).toBe(6);
    });
  });
});
