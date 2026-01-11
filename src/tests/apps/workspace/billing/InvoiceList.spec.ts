// src/tests/apps/workspace/billing/InvoiceList.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import InvoiceList from '@/apps/workspace/billing/InvoiceList.vue';
import { nextTick } from 'vue';

// Mock HeadlessUI components (none used in this component, but keep for consistency)
vi.mock('@headlessui/vue', () => ({}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock BillingLayout component
vi.mock('@/shared/components/layout/BillingLayout.vue', () => ({
  default: {
    name: 'BillingLayout',
    template: '<div class="billing-layout"><slot /></div>',
  },
}));

// Mock BasicFormAlerts component
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="error-alert">{{ error }}</div>',
    props: ['error', 'success'],
  },
}));

// Mock vue-router with isNavigationFailure for classifyError
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  useRoute: () => ({ params: {} }),
  isNavigationFailure: () => false,
}));

// RouterLink stub component
const RouterLinkStub = {
  name: 'RouterLink',
  template: '<a class="router-link" :data-to="JSON.stringify(to)"><slot /></a>',
  props: ['to'],
};

// Mock BillingService
const mockListInvoices = vi.fn();

vi.mock('@/services/billing.service', () => ({
  BillingService: {
    listInvoices: (...args: unknown[]) => mockListInvoices(...args),
  },
}));

// Mock organizationStore
const mockOrganizations = vi.fn(() => [
  { id: 'org_1', extid: 'org_ext_1', display_name: 'Test Org' },
]);
const mockFetchOrganizations = vi.fn();

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    organizations: mockOrganizations(),
    fetchOrganizations: mockFetchOrganizations,
  }),
}));

// Test data
const mockInvoices = [
  {
    id: 'inv_123',
    number: 'INV-001',
    created: 1704067200, // Jan 1, 2024
    amount: 2900,
    currency: 'usd',
    status: 'paid',
    invoice_pdf: 'https://stripe.com/invoices/inv_123.pdf',
    hosted_invoice_url: 'https://invoice.stripe.com/inv_123',
  },
  {
    id: 'inv_456',
    number: 'INV-002',
    created: 1706745600, // Feb 1, 2024
    amount: 9900,
    currency: 'usd',
    status: 'pending',
    invoice_pdf: null,
    hosted_invoice_url: 'https://invoice.stripe.com/inv_456',
  },
  {
    id: 'inv_789',
    number: 'INV-003',
    created: 1709251200, // Mar 1, 2024
    amount: 5000,
    currency: 'usd',
    status: 'failed',
    invoice_pdf: null,
    hosted_invoice_url: null,
  },
];

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        billing: {
          invoices: {
            title: 'Invoices',
            invoice_date: 'Date',
            invoice_amount: 'Amount',
            invoice_status: 'Status',
            invoice_download: 'Download',
            no_invoices: 'No invoices yet',
            load_error: 'Failed to load invoices',
            paid: 'Paid',
            pending: 'Pending',
            failed: 'Failed',
          },
          overview: {
            organization_selector: 'Select Organization',
            no_organizations_title: 'No organizations found',
          },
        },
        COMMON: {
          loading: 'Loading...',
        },
      },
    },
  },
});

describe('InvoiceList', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockListInvoices.mockReset();
    mockFetchOrganizations.mockReset();
    mockOrganizations.mockReturnValue([
      { id: 'org_1', extid: 'org_ext_1', display_name: 'Test Org' },
    ]);
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (waitForLoad = true) => {
    const component = mount(InvoiceList, {
      global: {
        plugins: [i18n, pinia],
        stubs: {
          RouterLink: RouterLinkStub,
        },
      },
    });

    if (waitForLoad) {
      await flushPromises();
    }

    return component;
  };

  describe('Loading State', () => {
    it('renders loading state initially', async () => {
      let resolveInvoices: (value: unknown) => void;
      const pendingPromise = new Promise(resolve => {
        resolveInvoices = resolve;
      });
      mockListInvoices.mockReturnValueOnce(pendingPromise);

      wrapper = await mountComponent(false);
      await nextTick();

      // Should show loading spinner
      const spinner = wrapper.find('[data-name="arrow-path"]');
      expect(spinner.exists()).toBe(true);
      expect(wrapper.text()).toContain('Loading...');

      // Clean up
      resolveInvoices!({ invoices: [] });
      await nextTick();
    });
  });

  describe('Invoice Table Rendering', () => {
    it('displays invoice rows after load', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      const table = wrapper.find('table');
      expect(table.exists()).toBe(true);

      const rows = wrapper.findAll('tbody tr');
      expect(rows.length).toBe(3);
    });

    it('shows invoice number in table', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      expect(wrapper.text()).toContain('INV-001');
      expect(wrapper.text()).toContain('INV-002');
      expect(wrapper.text()).toContain('INV-003');
    });
  });

  describe('Empty State', () => {
    it('shows empty state when no invoices', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: [] });
      wrapper = await mountComponent();

      expect(wrapper.text()).toContain('No invoices yet');
      // Should show the empty state icon
      const emptyIcon = wrapper.find('[data-name="document-text"]');
      expect(emptyIcon.exists()).toBe(true);
    });

    it('shows link to plans in empty state', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: [] });
      wrapper = await mountComponent();

      // Check for the router-link element in the empty state
      const link = wrapper.find('a.router-link');
      expect(link.exists()).toBe(true);
      // Verify it links to Billing Plans route
      expect(link.attributes('data-to')).toContain('Billing Plans');
    });
  });

  describe('Currency Formatting', () => {
    it('formats invoice amount correctly', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      // $29.00 from 2900 cents
      expect(wrapper.text()).toContain('$29.00');
      // $99.00 from 9900 cents
      expect(wrapper.text()).toContain('$99.00');
      // $50.00 from 5000 cents
      expect(wrapper.text()).toContain('$50.00');
    });
  });

  describe('Status Badge Display', () => {
    it('shows invoice status badge with correct styling', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      // Check that status text is displayed
      expect(wrapper.text()).toContain('Paid');
      expect(wrapper.text()).toContain('Pending');
      expect(wrapper.text()).toContain('Failed');

      // Check for status badge classes
      const badges = wrapper.findAll('span.inline-flex');

      // Find paid badge (green)
      const paidBadge = badges.find(b => b.text() === 'Paid');
      expect(paidBadge?.classes()).toContain('bg-green-100');

      // Find pending badge (yellow)
      const pendingBadge = badges.find(b => b.text() === 'Pending');
      expect(pendingBadge?.classes()).toContain('bg-yellow-100');

      // Find failed badge (red)
      const failedBadge = badges.find(b => b.text() === 'Failed');
      expect(failedBadge?.classes()).toContain('bg-red-100');
    });
  });

  describe('Download Functionality', () => {
    it('shows download button when invoice_pdf is available', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      const downloadButtons = wrapper.findAll('button').filter(
        btn => btn.text().includes('Download')
      );
      // First two invoices have download URLs
      expect(downloadButtons.length).toBe(2);
    });

    it('shows dash when no download URL available', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      const rows = wrapper.findAll('tbody tr');
      // Third invoice has no download URL - should show dash
      const thirdRowLastCell = rows[2].findAll('td').at(-1);
      expect(thirdRowLastCell?.text()).toBe('-');
    });

    it('calls window.open when download button is clicked', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      const windowOpenSpy = vi.spyOn(window, 'open').mockImplementation(() => null);

      wrapper = await mountComponent();

      const downloadButton = wrapper.findAll('button').find(
        btn => btn.text().includes('Download')
      );
      await downloadButton?.trigger('click');

      expect(windowOpenSpy).toHaveBeenCalledWith(
        'https://stripe.com/invoices/inv_123.pdf',
        '_blank'
      );

      windowOpenSpy.mockRestore();
    });
  });

  describe('Error Handling', () => {
    it('handles API error gracefully', async () => {
      mockListInvoices.mockRejectedValueOnce(new Error('Network error'));
      wrapper = await mountComponent();

      const errorAlert = wrapper.find('[data-testid="error-alert"]');
      expect(errorAlert.exists()).toBe(true);
      expect(errorAlert.text()).toContain('Network error');
    });

    it('shows error when organization has no extid', async () => {
      mockOrganizations.mockReturnValue([
        { id: 'org_1', extid: '', display_name: 'Test Org' },
      ]);

      wrapper = await mountComponent();

      const errorAlert = wrapper.find('[data-testid="error-alert"]');
      expect(errorAlert.exists()).toBe(true);
      expect(errorAlert.text()).toContain('Failed to load invoices');
    });
  });

  describe('API Integration', () => {
    it('calls listInvoices with correct org extid', async () => {
      mockListInvoices.mockResolvedValueOnce({ invoices: mockInvoices });
      wrapper = await mountComponent();

      expect(mockListInvoices).toHaveBeenCalledWith('org_ext_1');
    });
  });
});
