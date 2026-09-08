// src/tests/apps/admin/AdminCustomerDetailRodauthAdminLink.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The outbound deep link from the customer detail page to the standalone
 * Rodauth Admin — the read-only use of the `accounts.external_id == extid`
 * join (rodauth-admin CHARTER §4, seam 1).
 *
 * The SERVER decides whether a link exists (full auth mode AND
 * RODAUTH_ADMIN_URL configured); the page only renders what it is handed. Two
 * things are pinned: null or an absent field renders the public id as plain
 * text with no link, and a URL renders as a new-tab link that fetches nothing.
 */

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  useRoute: () => ({ params: { id: 'ur_alice' } }),
}));

vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: vi.fn() }),
}));

vi.mock('@/utils/navigation', () => ({
  hardNavigate: vi.fn(),
}));

vi.mock('@/utils/format', () => ({
  formatDisplayDateTime: (d: Date) => `DT:${d.toISOString()}`,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminCustomerDetail from '@/apps/admin/views/AdminCustomerDetail.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const PUBLIC_ID = 'ur_alice';
const ADMIN_LINK = 'http://127.0.0.1:9292/account?q=ur_alice';

function detailPayload(rodauthAdminAccountUrl: string | null | undefined) {
  const details: Record<string, unknown> = {
    secrets: { count: 0, items: [] },
    receipts: { count: 0, items: [] },
    organizations: [],
    billing: {
      enabled: false,
      plan_id: 'basic',
      organization: null,
      stripe: {
        available: false,
        reason: 'Billing is not configured',
        customer_id: null,
        dashboard_url: null,
        subscription: null,
        latest_invoice: null,
      },
    },
    stats: { secrets_created: 0, secrets_shared: 0, emails_sent: 0 },
  };
  if (rodauthAdminAccountUrl !== undefined) {
    details.rodauth_admin_account_url = rodauthAdminAccountUrl;
  }
  return {
    shrimp: '',
    record: {
      extid: PUBLIC_ID,
      email: 'alice@example.com',
      role: 'customer',
      verified: true,
      suspended: false,
      suspended_at: null,
      suspended_by: null,
      suspended_reason: null,
      created: 1700000000,
      updated: 1700000100,
      last_login: 1700000200,
      planid: 'basic',
      locale: 'en',
    },
    details,
  };
}

const mountView = () =>
  mount(AdminCustomerDetail, {
    props: { id: PUBLIC_ID },
    global: {
      plugins: [i18n],
      stubs: {
        AdminCustomerSessionsSection: true,
        AdminAccountDiagnosticsSection: true,
        AdminConfirmDialog: true,
      },
    },
  });

const link = (w: VueWrapper) => w.find('[data-testid="rodauth-admin-link"]');

describe('AdminCustomerDetail — Rodauth Admin deep link', () => {
  let wrapper: VueWrapper;

  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  async function mountWith(url: string | null | undefined): Promise<void> {
    mockApi.get.mockResolvedValue({ data: detailPayload(url) });
    wrapper = mountView();
    await flushPromises();
  }

  it('renders a new-tab link keyed by the server-built URL when present', async () => {
    await mountWith(ADMIN_LINK);

    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
    expect(link(wrapper).exists()).toBe(true);
    expect(link(wrapper).attributes('href')).toBe(ADMIN_LINK);
    expect(link(wrapper).attributes('target')).toBe('_blank');
    expect(link(wrapper).attributes('rel')).toContain('noopener');
    // The link is a hand-over, never a fetch: one GET (the detail itself).
    expect(mockApi.get).toHaveBeenCalledTimes(1);
  });

  it('renders no link when the server sends null (unset URL or simple mode)', async () => {
    await mountWith(null);

    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
    expect(link(wrapper).exists()).toBe(false);
    expect(wrapper.text()).toContain(PUBLIC_ID);
  });

  it('still parses and renders when the field is absent (deploy skew)', async () => {
    await mountWith(undefined);

    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
    expect(link(wrapper).exists()).toBe(false);
  });
});
