// src/tests/shared/components/modals/PlanPreviewModal.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * PlanPreviewModal is a colonel mutation surface: its submits POST to
 * /api/colonel/entitlement-preview. #4497 item 13 requires that the submit
 * paths refuse to fire while auth authority is not established, even if a
 * caller opens the modal or state flips mid-interaction. The UserMenu trigger
 * already aria-disables the entry point; this test pins the internal guard.
 */

const apiPostMock = vi.fn();
const apiGetMock = vi.fn();
vi.mock('@/api', () => ({
  createApi: () => ({
    post: (...args: unknown[]) => apiPostMock(...args),
    get: (...args: unknown[]) => apiGetMock(...args),
  }),
}));

// Test i18n is pass-through (ADR-014), so labels render as raw keys — not
// asserted here; the test targets behaviour (POST called or not).
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

vi.mock('@/shared/components/closet/ListSkeleton.vue', () => ({
  default: { name: 'ListSkeleton', template: '<div class="list-skeleton" />' },
}));

vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: {
    name: 'DialogTitle',
    template: '<h3><slot /></h3>',
    props: ['as', 'class'],
  },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: {
    name: 'TransitionChild',
    template: '<div><slot /></div>',
    props: ['as', 'enter', 'enterFrom', 'enterTo', 'leave', 'leaveFrom', 'leaveTo'],
  },
}));

import PlanPreviewModal from '@/shared/components/modals/PlanPreviewModal.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

describe('PlanPreviewModal — #4497 item 13 submit gating', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    apiGetMock.mockResolvedValue({
      data: {
        plans: [
          { planid: 'basic_month', name: 'Basic', description: 'basic plan' },
          { planid: 'pro_month', name: 'Pro', description: 'pro plan' },
        ],
        source: 'stripe',
      },
    });
    apiPostMock.mockResolvedValue({ data: {} });
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
  });

  function seed(status: 'authenticated' | 'unavailable' | 'checking') {
    const bootstrap = useBootstrapStore();
    // Enough state so `protectedActionsAvailable` derives strictly from status.
    bootstrap.$patch({
      authStatus: status,
      authenticated: status === 'authenticated',
      cust:
        status === 'authenticated'
          ? ({ custid: 'cust_x', email: 'x@example.com' } as never)
          : (undefined as never),
    } as never);
  }

  async function mountModal(): Promise<VueWrapper> {
    const w = mount(PlanPreviewModal, {
      props: { isOpen: true },
      global: { plugins: [i18n] },
    });
    await flushPromises();
    return w;
  }

  it('activate DOES POST when authority is established (authenticated)', async () => {
    seed('authenticated');
    wrapper = await mountModal();

    const planButton = wrapper
      .findAll('button[type="button"]')
      .find((b) => b.text().includes('Basic'));
    expect(planButton).toBeTruthy();

    await planButton!.trigger('click');
    // Do NOT await the post-submit syncPreviewState — it drives real
    // authStore.refresh() and organizationStore.fetchOrganizations() calls
    // that fall outside this spec's scope. The guard's job is proven by the
    // POST landing at all.
    expect(apiPostMock).toHaveBeenCalledWith(
      '/api/colonel/entitlement-preview',
      { planid: 'basic_month' }
    );
  });

  it('activate refuses to POST when authStatus is unavailable and closes the modal', async () => {
    seed('unavailable');
    wrapper = await mountModal();

    const planButton = wrapper
      .findAll('button[type="button"]')
      .find((b) => b.text().includes('Basic'));
    expect(planButton).toBeTruthy();

    await planButton!.trigger('click');
    await flushPromises();

    // The internal guard fires: no protected endpoint is hit, and the modal
    // emits close so the operator is not left in a dead surface.
    expect(apiPostMock).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('activate refuses to POST when authStatus is checking', async () => {
    seed('checking');
    wrapper = await mountModal();

    const planButton = wrapper
      .findAll('button[type="button"]')
      .find((b) => b.text().includes('Basic'));
    await planButton!.trigger('click');
    await flushPromises();

    expect(apiPostMock).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
