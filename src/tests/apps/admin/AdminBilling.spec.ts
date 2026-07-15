// src/tests/apps/admin/AdminBilling.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminBilling from '@/apps/admin/views/AdminBilling.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const CATALOG_URL = '/api/colonel/billing/catalog';

function plan(overrides: Record<string, unknown> = {}) {
  return {
    planid: 'plan_x',
    name: 'Plan X',
    tier: 'single_team',
    tenancy: 'shared',
    region: 'US',
    display_order: 1,
    show_on_plans_page: true,
    description: null,
    entitlements: ['create_secrets'],
    limits: { 'teams.max': '1' },
    ...overrides,
  };
}

/** A catalog with one in-sync plan, one config-only, one live-only, one changed. */
function catalogPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      source: 'stripe',
      stripe_configured: true,
      config_plans: [
        plan({ planid: 'free_v1', name: 'Free', entitlements: ['create_secrets'] }),
        plan({ planid: 'legacy_v1', name: 'Legacy' }), // config only
        plan({
          planid: 'identity_plus_v1',
          name: 'Identity+',
          entitlements: ['create_secrets', 'custom_domains'],
        }),
      ],
      live_plans: [
        plan({ planid: 'free_v1', name: 'Free', entitlements: ['create_secrets'] }),
        plan({ planid: 'new_v2', name: 'New' }), // live only
        plan({
          planid: 'identity_plus_v1',
          name: 'Identity+',
          entitlements: ['create_secrets'], // drift: entitlements differ
        }),
      ],
      drift: {
        in_sync: false,
        only_in_config: ['legacy_v1'],
        only_in_live: ['new_v2'],
        changed: [{ planid: 'identity_plus_v1', name: 'Identity+', fields: ['entitlements'] }],
      },
    },
  };
}

function localConfigPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      source: 'local_config',
      stripe_configured: false,
      config_plans: [plan({ planid: 'free_v1', name: 'Free' })],
      live_plans: [],
      drift: { in_sync: false, only_in_config: ['free_v1'], only_in_live: [], changed: [] },
    },
  };
}

// Stub JsonViewer (avoid clipboard machinery) and DetailDrawer (always render
// its slot so the diff content is assertable without headlessui teleport).
const jsonViewerStub = {
  name: 'JsonViewer',
  props: ['data', 'expandDepth', 'testid'],
  template: '<div :data-testid="testid" />',
};
const detailDrawerStub = {
  name: 'DetailDrawer',
  props: ['open', 'title', 'subtitle', 'testid'],
  template: '<div :data-testid="testid"><slot /></div>',
};

const mountView = (pinia: ReturnType<typeof createPinia>) =>
  mount(AdminBilling, {
    global: {
      plugins: [pinia, i18n],
      stubs: { JsonViewer: jsonViewerStub, DetailDrawer: detailDrawerStub },
    },
  });

describe('AdminBilling (read-only billing catalog drift — ticket #45)', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('issues the single catalog GET on mount', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView(pinia);
    await flushPromises();
    expect(mockApi.get).toHaveBeenCalledWith(CATALOG_URL, undefined);
  });

  it('renders the union of config + live plans with per-plan drift status', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    const table = wrapper.find('[data-testid="billing-plans-table"]');
    expect(table.exists()).toBe(true);
    // Union: free_v1, identity_plus_v1, legacy_v1 (config only), new_v2 (live only)
    const text = table.text();
    expect(text).toContain('free_v1');
    expect(text).toContain('legacy_v1');
    expect(text).toContain('new_v2');
    expect(text).toContain('identity_plus_v1');
    // The changed plan surfaces which fields drifted.
    expect(text).toContain('entitlements');
    // Drift summary is not in-sync, so the in-sync banner is absent.
    expect(wrapper.find('[data-testid="billing-in-sync"]').exists()).toBe(false);
  });

  it('opens the side-by-side diff drawer for a plan present on both sides', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="billing-diff-identity_plus_v1"]').trigger('click');
    await flushPromises();

    // Both config and live JSON panels render for a plan on both sides.
    expect(wrapper.find('[data-testid="billing-diff-config-json"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-diff-live-json"]').exists()).toBe(true);
  });

  it('shows a config-absent placeholder in the diff for a live-only plan', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    await wrapper.find('[data-testid="billing-diff-new_v2"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-diff-config-absent"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-diff-live-json"]').exists()).toBe(true);
  });

  it('warns when the source is local_config (drift cannot be evaluated)', async () => {
    mockApi.get.mockResolvedValue({ data: localConfigPayload() });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-local-config-warning"]').exists()).toBe(true);
  });

  it('renders the in-sync banner when the catalog matches', async () => {
    const payload = catalogPayload();
    payload.details.config_plans = [plan({ planid: 'free_v1', name: 'Free' })];
    payload.details.live_plans = [plan({ planid: 'free_v1', name: 'Free' })];
    payload.details.drift = { in_sync: true, only_in_config: [], only_in_live: [], changed: [] };
    mockApi.get.mockResolvedValue({ data: payload });
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-in-sync"]').exists()).toBe(true);
  });

  it('shows an error state with retry when the GET fails', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView(pinia);
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-plans-table"]').exists()).toBe(false);
  });

  it('shows the loading state while the request is in flight', async () => {
    mockApi.get.mockReturnValue(new Promise(() => {}));
    wrapper = mountView(pinia);
    await flushPromises();
    expect(wrapper.find('[data-testid="billing-loading"]').exists()).toBe(true);
  });
});
