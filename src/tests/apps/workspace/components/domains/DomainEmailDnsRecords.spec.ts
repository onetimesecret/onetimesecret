// src/tests/apps/workspace/components/domains/DomainEmailDnsRecords.spec.ts
//
// Tests for DomainEmailDnsRecords.vue covering:
// 1. DNS records table rendering with correct columns
// 2. Per-record status indicators with correct colors
// 3. Validate event emission on re-validate button click
// 4. Validation status banner (verified/pending/failed)
// 5. Empty state when no records
// 6. Last validated timestamp display

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
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

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          email: {
            dns_records_title: 'DNS Records',
            dns_records_description: 'Add the following DNS records to your domain to authenticate email sending.',
            dns_column_type: 'Type',
            dns_column_name: 'Name',
            dns_column_value: 'Value',
            revalidate: 'Re-validate',
            validating: 'Validating...',
            domain_verified: 'Domain email sending is verified',
            validation_failed: 'Validation failed. Please check your DNS records.',
            status_verified: 'Verified',
            status_pending: 'Pending',
            status_failed: 'Failed',
            last_validated: 'Last validated',
            copy: 'Copy',
          },
        },
        COMMON: {
          status: 'Status',
        },
      },
    },
  },
});

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
    isValidating: boolean;
  }> = {}) => {
    return mount(DomainEmailDnsRecords, {
      props: {
        dnsRecords: props.dnsRecords ?? mockDnsRecords,
        validationStatus: props.validationStatus ?? 'pending',
        lastValidatedAt: props.lastValidatedAt ?? null,
        isValidating: props.isValidating ?? false,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  // ─────────────────────────────────────────────────────────────────────────
  // DNS records table
  // ─────────────────────────────────────────────────────────────────────────

  describe('DNS records table', () => {
    it('renders a table when records are present', () => {
      wrapper = mountComponent();

      const table = wrapper.find('table');
      expect(table.exists()).toBe(true);
    });

    it('renders correct column headers', () => {
      wrapper = mountComponent();

      const headers = wrapper.findAll('th');
      expect(headers).toHaveLength(4); // Type, Name, Value, Status (sr-only)

      expect(headers[0].text()).toBe('Type');
      expect(headers[1].text()).toBe('Name');
      expect(headers[2].text()).toBe('Value');
    });

    it('renders one row per DNS record', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      expect(rows).toHaveLength(3);
    });

    it('displays record type in each row', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      expect(rows[0].text()).toContain('TXT');
      expect(rows[1].text()).toContain('CNAME');
      expect(rows[2].text()).toContain('TXT');
    });

    it('displays record name in each row', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      expect(rows[0].text()).toContain('_dmarc.example.com');
      expect(rows[1].text()).toContain('em._domainkey.example.com');
    });

    it('displays record value in each row', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      expect(rows[0].text()).toContain('v=DMARC1; p=none');
      expect(rows[1].text()).toContain('dkim.sendgrid.net');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Per-record status indicators
  // ─────────────────────────────────────────────────────────────────────────

  describe('Per-record status indicators', () => {
    it('shows Verified label for verified records', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      // First record has status 'verified'
      expect(rows[0].text()).toContain('Verified');
    });

    it('shows Pending label for pending records', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      // Second record has status 'pending'
      expect(rows[1].text()).toContain('Pending');
    });

    it('shows Failed label for failed records', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      // Third record has status 'failed'
      expect(rows[2].text()).toContain('Failed');
    });

    it('applies emerald color classes for verified status', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      const statusCell = rows[0].findAll('td').at(-1);
      const statusSpan = statusCell!.find('.inline-flex');
      expect(statusSpan.classes()).toContain('text-emerald-600');
    });

    it('applies amber color classes for pending status', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      const statusCell = rows[1].findAll('td').at(-1);
      const statusSpan = statusCell!.find('.inline-flex');
      expect(statusSpan.classes()).toContain('text-amber-500');
    });

    it('applies rose color classes for failed status', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      const statusCell = rows[2].findAll('td').at(-1);
      const statusSpan = statusCell!.find('.inline-flex');
      expect(statusSpan.classes()).toContain('text-rose-600');
    });

    it('uses correct icon name for verified records', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      const statusCell = rows[0].findAll('td').at(-1);
      const icon = statusCell!.find('.o-icon');
      expect(icon.attributes('data-icon-name')).toBe('check-circle-solid');
    });

    it('uses correct icon name for pending records', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      const statusCell = rows[1].findAll('td').at(-1);
      const icon = statusCell!.find('.o-icon');
      expect(icon.attributes('data-icon-name')).toBe('clock');
    });

    it('uses correct icon name for failed records', () => {
      wrapper = mountComponent();

      const rows = wrapper.findAll('tbody tr');
      const statusCell = rows[2].findAll('td').at(-1);
      const icon = statusCell!.find('.o-icon');
      expect(icon.attributes('data-icon-name')).toBe('x-circle-solid');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Validate event
  // ─────────────────────────────────────────────────────────────────────────

  describe('Validate event', () => {
    it('emits validate event when re-validate button is clicked', async () => {
      wrapper = mountComponent();

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('Re-validate'));
      expect(revalidateButton).toBeDefined();

      await revalidateButton!.trigger('click');

      expect(wrapper.emitted('validate')).toBeTruthy();
      expect(wrapper.emitted('validate')).toHaveLength(1);
    });

    it('disables re-validate button when isValidating is true', () => {
      wrapper = mountComponent({ isValidating: true });

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('Validating...'));
      expect(revalidateButton).toBeDefined();
      expect(revalidateButton!.attributes('disabled')).toBeDefined();
    });

    it('shows "Validating..." text when isValidating is true', () => {
      wrapper = mountComponent({ isValidating: true });

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('Validating...'));
      expect(revalidateButton).toBeDefined();
    });

    it('shows "Re-validate" text when not validating', () => {
      wrapper = mountComponent({ isValidating: false });

      const buttons = wrapper.findAll('button[type="button"]');
      const revalidateButton = buttons.find((b) => b.text().includes('Re-validate'));
      expect(revalidateButton).toBeDefined();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Validation status banner
  // ─────────────────────────────────────────────────────────────────────────

  describe('Validation status banner', () => {
    it('shows verified banner with role=status when status is verified', () => {
      wrapper = mountComponent({ validationStatus: 'verified' });

      const banner = wrapper.find('[role="status"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('Domain email sending is verified');
    });

    it('shows failed banner with role=alert when status is failed', () => {
      wrapper = mountComponent({ validationStatus: 'failed' });

      const banner = wrapper.find('[role="alert"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('Validation failed');
    });

    it('shows pending banner with role=status when status is pending', () => {
      wrapper = mountComponent({ validationStatus: 'pending' });

      const banners = wrapper.findAll('[role="status"]');
      // There should be a status banner showing pending state
      const pendingBanner = banners.find((b) => b.text().includes('Pending'));
      expect(pendingBanner).toBeDefined();
    });

    it('shows last validated timestamp in verified banner', () => {
      const lastValidated = new Date('2025-06-15T14:30:00Z');
      wrapper = mountComponent({
        validationStatus: 'verified',
        lastValidatedAt: lastValidated,
      });

      const banner = wrapper.find('[role="status"]');
      expect(banner.text()).toContain('Last validated');
    });

    it('shows last validated timestamp in failed banner', () => {
      const lastValidated = new Date('2025-06-15T14:30:00Z');
      wrapper = mountComponent({
        validationStatus: 'failed',
        lastValidatedAt: lastValidated,
      });

      const banner = wrapper.find('[role="alert"]');
      expect(banner.text()).toContain('Last validated');
    });

    it('does not show timestamp when lastValidatedAt is null', () => {
      wrapper = mountComponent({
        validationStatus: 'verified',
        lastValidatedAt: null,
      });

      const banner = wrapper.find('[role="status"]');
      expect(banner.text()).not.toContain('Last validated');
    });

    it('uses emerald background for verified banner', () => {
      wrapper = mountComponent({ validationStatus: 'verified' });

      const banner = wrapper.find('[role="status"]');
      expect(banner.classes()).toContain('bg-emerald-50');
    });

    it('uses rose background for failed banner', () => {
      wrapper = mountComponent({ validationStatus: 'failed' });

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
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────

  describe('Empty state', () => {
    it('shows empty state when no DNS records', () => {
      wrapper = mountComponent({ dnsRecords: [] });

      const table = wrapper.find('table');
      expect(table.exists()).toBe(false);

      // Should show the dashed border empty state
      const emptyState = wrapper.find('.border-dashed');
      expect(emptyState.exists()).toBe(true);
    });

    it('shows description text in empty state', () => {
      wrapper = mountComponent({ dnsRecords: [] });

      const emptyState = wrapper.find('.border-dashed');
      expect(emptyState.text()).toContain('Add the following DNS records');
    });

    it('does not show table when records list is empty', () => {
      wrapper = mountComponent({ dnsRecords: [] });

      expect(wrapper.find('table').exists()).toBe(false);
      expect(wrapper.find('tbody').exists()).toBe(false);
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
      expect(heading.text()).toBe('DNS Records');
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
        b.attributes('aria-label')?.includes('Copy')
      );
      expect(filteredButtons.length).toBe(6);
    });
  });
});
