// src/tests/apps/admin/AdminCheckoutLinkModal.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = { get: vi.fn(), post: vi.fn(), delete: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

// `isNavigationFailure` is reached by the shared error classifier on every
// failed mutation — the mock must provide it or the classifier throws.
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  isNavigationFailure: () => false,
  NavigationFailureType: { aborted: 4, cancelled: 8, duplicated: 16 },
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

// CopyButton touches navigator.clipboard; stub it but keep the text prop
// observable so the copy affordance can be asserted against the real URL.
vi.mock('@/shared/components/ui/CopyButton.vue', () => ({
  default: {
    name: 'CopyButton',
    template: '<button class="copy-button" :data-testid="testid" :data-text="text" />',
    props: ['text', 'tooltip', 'testid'],
  },
}));

// Render the headlessui modal synchronously and IN-PLACE (the real Dialog
// teleports its panel to <body>, escaping the mounted wrapper).
vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: "<div role=\"dialog\" @close=\"$emit('close')\"><slot /></div>",
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel" :data-testid="$attrs[\'data-testid\']"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: { name: 'DialogTitle', template: '<h3><slot /></h3>', props: ['as', 'class'] },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: { name: 'TransitionChild', template: '<div><slot /></div>', props: ['as'] },
}));

import AdminCheckoutLinkModal from '@/apps/admin/components/AdminCheckoutLinkModal.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const ENDPOINT = '/api/colonel/users/ur_abc123/checkout-link';

const PLANS = [
  { planid: 'identity_plus_v1', label: 'Identity Plus (identity_plus_v1)' },
  { planid: 'global_elite_v1', label: 'Global Elite (global_elite_v1)' },
];

function ackPayload() {
  return {
    shrimp: '',
    record: {
      checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_xyz',
      session_id: 'cs_test_xyz',
      plan_id: 'identity_plus_v1_month',
      price_id: 'price_123',
      expires_at: Math.floor(Date.now() / 1000) + 24 * 3600,
    },
    details: { region: 'eu' },
  };
}

function mountModal(props: Partial<InstanceType<typeof AdminCheckoutLinkModal>['$props']> = {}) {
  return mount(AdminCheckoutLinkModal, {
    props: {
      open: true,
      endpoint: ENDPOINT,
      subject: 'ur_abc123',
      plans: PLANS,
      defaultPlan: 'identity_plus_v1',
      ...props,
    },
    global: { plugins: [createPinia(), i18n] },
  });
}

describe('AdminCheckoutLinkModal', () => {
  let wrapper: VueWrapper | null = null;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  it('renders a plan SELECT when a catalog is supplied, preselecting defaultPlan', () => {
    wrapper = mountModal();
    const select = wrapper.find('[data-testid="checkout-link-plan-select"]');
    expect(select.exists()).toBe(true);
    expect((select.element as HTMLSelectElement).value).toBe('identity_plus_v1');
    expect(wrapper.find('[data-testid="checkout-link-plan-input"]').exists()).toBe(false);
  });

  it('degrades to a free-text plan input when the catalog is empty', () => {
    wrapper = mountModal({ plans: [], defaultPlan: 'legacy_plan_v0' });
    const input = wrapper.find('[data-testid="checkout-link-plan-input"]');
    expect(input.exists()).toBe(true);
    expect((input.element as HTMLInputElement).value).toBe('legacy_plan_v0');
  });

  it('POSTs the contract body and shows the URL + copy + expiry on success', async () => {
    mockApi.post.mockResolvedValue({ data: ackPayload() });
    wrapper = mountModal();

    await wrapper.find('[data-testid="checkout-link-cycle-yearly"]').setValue();
    await wrapper.find('[data-testid="checkout-link-submit"]').trigger('click');
    await flushPromises();

    expect(mockApi.post).toHaveBeenCalledWith(ENDPOINT, {
      plan: 'identity_plus_v1',
      billing_cycle: 'yearly',
      allow_promotion_codes: false,
    });

    expect(wrapper.find('[data-testid="checkout-link-url"]').text()).toBe(
      'https://checkout.stripe.com/c/pay/cs_test_xyz'
    );
    expect(
      wrapper.find('[data-testid="checkout-link-copy"]').attributes('data-text')
    ).toBe('https://checkout.stripe.com/c/pay/cs_test_xyz');
    // The shared test i18n is pass-through (returns the key, no interpolation),
    // so assert the expiry line renders through the right key.
    expect(wrapper.find('[data-testid="checkout-link-expiry"]').text()).toBe(
      'web.admin.customers.actions.checkoutLink.expiry'
    );
    // Form is gone — no double-submit path.
    expect(wrapper.find('[data-testid="checkout-link-form"]').exists()).toBe(false);
  });

  it('surfaces an in-modal error when the 2xx ack is unreadable (parse failure)', async () => {
    mockApi.post.mockResolvedValue({ data: { shrimp: '', record: {}, details: {} } });
    wrapper = mountModal();

    await wrapper.find('[data-testid="checkout-link-submit"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="checkout-link-result"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="checkout-link-error"]').exists()).toBe(true);
  });

  it('surfaces an API failure in-modal and keeps the form for retry', async () => {
    mockApi.post.mockRejectedValue({
      response: { status: 422, data: { error: 'Unknown plan family' } },
    });
    wrapper = mountModal();

    await wrapper.find('[data-testid="checkout-link-submit"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="checkout-link-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="checkout-link-form"]').exists()).toBe(true);
  });

  it('resets state (fresh form, no stale URL) on re-open', async () => {
    mockApi.post.mockResolvedValue({ data: ackPayload() });
    wrapper = mountModal();

    await wrapper.find('[data-testid="checkout-link-submit"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="checkout-link-result"]').exists()).toBe(true);

    await wrapper.setProps({ open: false });
    await wrapper.setProps({ open: true });

    expect(wrapper.find('[data-testid="checkout-link-result"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="checkout-link-form"]').exists()).toBe(true);
  });
});
