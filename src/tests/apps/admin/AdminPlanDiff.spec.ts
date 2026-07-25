// src/tests/apps/admin/AdminPlanDiff.spec.ts

import { AxiosError } from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** Build a real AxiosError so the 404 branch of useResourceFetch is exercised. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

const mockApi = { get: vi.fn(), post: vi.fn(), delete: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

const pushMock = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: pushMock }),
  useRoute: () => ({ params: { planid: 'identity_plus_v1' } }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import AdminPlanDiff from '@/apps/admin/views/AdminPlanDiff.vue';
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

/** One plan on both sides (drifting), one config-only, one live-only. */
function catalogPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      source: 'stripe',
      stripe_configured: true,
      config_plans: [
        plan({
          planid: 'identity_plus_v1',
          name: 'Identity+',
          entitlements: ['create_secrets', 'custom_domains'],
        }),
        plan({ planid: 'legacy_v1', name: 'Legacy' }),
      ],
      live_plans: [
        plan({ planid: 'identity_plus_v1', name: 'Identity+', entitlements: ['create_secrets'] }),
        plan({ planid: 'new_v2', name: 'New' }),
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

// Stub JsonViewer: its clipboard machinery is not under test here.
const jsonViewerStub = {
  name: 'JsonViewer',
  props: ['data', 'expandDepth', 'testid'],
  template: '<div :data-testid="testid" />',
};

const mountView = (planid: string) =>
  mount(AdminPlanDiff, {
    props: { planid },
    global: { plugins: [i18n], stubs: { JsonViewer: jsonViewerStub } },
  });

describe('AdminPlanDiff (full-page config-vs-live plan comparison)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  it('fetches the catalog itself so a deep link / refresh works', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    // No reliance on navigation state: the page issues its own GET on mount.
    expect(mockApi.get).toHaveBeenCalledWith(CATALOG_URL, undefined);
  });

  it('renders both JSON panels for a plan present on both sides', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-diff-config-json"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-diff-live-json"]').exists()).toBe(true);
    // The drifted field names are surfaced from the server's drift summary.
    expect(wrapper.find('[data-testid="plan-diff-fields"]').text()).toContain('entitlements');
    expect(wrapper.find('[data-testid="plan-diff-planid"]').text()).toBe('identity_plus_v1');
  });

  it('hands the selected plan (not the whole catalog) to each JSON panel', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    const viewers = wrapper.findAllComponents(jsonViewerStub);
    expect(viewers).toHaveLength(2);
    expect((viewers[0].props('data') as { planid: string }).planid).toBe('identity_plus_v1');
    expect((viewers[0].props('data') as { entitlements: string[] }).entitlements).toEqual([
      'create_secrets',
      'custom_domains',
    ]);
    expect((viewers[1].props('data') as { entitlements: string[] }).entitlements).toEqual([
      'create_secrets',
    ]);
  });

  it('shows a config-absent placeholder for a live-only plan', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('new_v2');
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-diff-config-absent"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-diff-live-json"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="plan-diff-status"]').text()).toContain('only_live');
  });

  it('shows a live-absent placeholder for a config-only plan', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('legacy_v1');
    await flushPromises();

    expect(wrapper.find('[data-testid="billing-diff-live-absent"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="billing-diff-config-json"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="plan-diff-status"]').text()).toContain('only_config');
  });

  it('renders a not-found state for a planid absent from the catalog', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('does_not_exist_v9');
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-not-found"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(false);
  });

  it('navigates back to the billing catalog', async () => {
    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    await wrapper.find('[data-testid="detail-back"]').trigger('click');
    expect(pushMock).toHaveBeenCalledWith({ name: 'AdminBilling' });
  });

  it('shows an error state with retry when the catalog GET fails', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-error"]').exists()).toBe(true);

    mockApi.get.mockResolvedValue({ data: catalogPayload() });
    await wrapper.find('[data-testid="detail-error"] button').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-content"]').exists()).toBe(true);
  });

  it('treats a 404 on the catalog endpoint as a load failure, not a missing plan', async () => {
    mockApi.get.mockRejectedValue(axiosError(404, { error: 'Not Found' }));
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="detail-not-found"]').exists()).toBe(false);
  });

  it('shows the loading state while the request is in flight', async () => {
    mockApi.get.mockReturnValue(new Promise(() => {}));
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    expect(wrapper.find('[data-testid="detail-loading"]').exists()).toBe(true);
  });

  it('warns when the catalog source is local_config', async () => {
    const payload = catalogPayload();
    payload.details.source = 'local_config';
    payload.details.stripe_configured = false;
    payload.details.live_plans = [];
    mockApi.get.mockResolvedValue({ data: payload });
    wrapper = mountView('identity_plus_v1');
    await flushPromises();

    expect(wrapper.find('[data-testid="plan-diff-local-config-warning"]').exists()).toBe(true);
  });
});
