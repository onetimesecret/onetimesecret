// src/tests/shared/components/modals/PlanPreviewModal.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * PlanPreviewModal is a colonel mutation surface: its submits POST to
 * /api/colonel/entitlement-preview. ADR-046#authority-action-gating requires that the submit
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
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

describe('PlanPreviewModal — submit gating (ADR-046#authority-action-gating)', () => {
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

/**
 * The override POST and the follow-up refresh (authStore.refresh +
 * organizationStore.fetchOrganizations) are separate failure modes. Once the
 * POST has succeeded the override is applied server-side, so a refresh failure
 * must not be reported as the override failing, and the modal must show the
 * applied state from the POST response.
 */
describe('PlanPreviewModal — override applied vs refresh failed', () => {
  let wrapper: VueWrapper | undefined;

  const PLANS = {
    plans: [
      { planid: 'basic_month', name: 'Basic', description: 'basic plan' },
      { planid: 'pro_month', name: 'Pro', description: 'pro plan' },
    ],
    source: 'stripe',
  };

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    apiGetMock.mockResolvedValue({ data: PLANS });
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({
      authStatus: 'authenticated',
      authenticated: true,
      cust: { custid: 'cust_x', email: 'x@example.com' } as never,
    } as never);
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
  });

  function stubSync(opts: {
    refresh?: 'applied' | 'failed';
    orgs?: 'resolve' | 'reject';
  }) {
    const authStore = useAuthStore();
    const organizationStore = useOrganizationStore();
    vi.spyOn(authStore, 'refresh').mockResolvedValue(opts.refresh ?? 'applied');
    const orgsSpy = vi.spyOn(organizationStore, 'fetchOrganizations');
    if (opts.orgs === 'reject') {
      orgsSpy.mockRejectedValue(new Error('Unable to load organizations. Please try again.'));
    } else {
      orgsSpy.mockResolvedValue([]);
    }
  }

  async function mountModal(): Promise<VueWrapper> {
    const w = mount(PlanPreviewModal, {
      props: { isOpen: true },
      global: { plugins: [i18n] },
    });
    await flushPromises();
    return w;
  }

  function planButton(w: VueWrapper, name: string) {
    const b = w.findAll('button[type="button"]').find((x) => x.text().includes(name));
    expect(b).toBeTruthy();
    return b!;
  }

  function errorText(w: VueWrapper): string | undefined {
    return w.find('.bg-red-50 p').exists() ? w.find('.bg-red-50 p').text() : undefined;
  }

  function cancelButton(w: VueWrapper) {
    const b = w.findAll('button[type="button"]').find((x) => x.text() === 'web.COMMON.word_cancel');
    expect(b).toBeTruthy();
    return b!;
  }

  describe('activate', () => {
    it('closes without error when the POST and the refresh both succeed', async () => {
      apiPostMock.mockResolvedValue({
        data: { status: 'active', test_planid: 'basic_month', test_plan_name: 'Basic' },
      });
      stubSync({ refresh: 'applied', orgs: 'resolve' });
      wrapper = await mountModal();

      await planButton(wrapper, 'Basic').trigger('click');
      await flushPromises();

      expect(errorText(wrapper)).toBeUndefined();
      expect(wrapper.emitted('close')).toBeTruthy();
      expect(useBootstrapStore().entitlement_preview_planid).toBe('basic_month');
      // An ordinary refresh would join a GET already in flight, and one served
      // before the POST committed would revert the fields just written.
      expect(useAuthStore().refresh).toHaveBeenCalledWith({
        kind: 'session-mutation',
        reason: 'plan-preview',
      });
    });

    it('reports the refresh failure, not the override, when fetchOrganizations rejects after a successful POST', async () => {
      apiPostMock.mockResolvedValue({
        data: { status: 'active', test_planid: 'basic_month', test_plan_name: 'Basic' },
      });
      stubSync({ refresh: 'applied', orgs: 'reject' });
      wrapper = await mountModal();

      await planButton(wrapper, 'Basic').trigger('click');
      await flushPromises();

      expect(errorText(wrapper)).toBe('web.colonel.activateTestModeRefreshFailed');
      // The modal stays open so the operator reads the message.
      expect(wrapper.emitted('close')).toBeFalsy();

      // The override DID apply: the modal reflects the server-confirmed state.
      const bootstrap = useBootstrapStore();
      expect(bootstrap.entitlement_preview_planid).toBe('basic_month');
      expect(bootstrap.entitlement_preview_plan_name).toBe('Basic');
      expect(wrapper.text()).toContain('web.colonel.previewModeActive');
      expect(planButton(wrapper, 'Basic').attributes('disabled')).toBeDefined();

      // Loading cleared: the other controls are usable again.
      expect(cancelButton(wrapper).attributes('disabled')).toBeUndefined();
      expect(planButton(wrapper, 'Pro').attributes('disabled')).toBeUndefined();
    });

    it('reports the refresh failure when the auth refresh resolves without applying a snapshot', async () => {
      apiPostMock.mockResolvedValue({
        data: { status: 'active', test_planid: 'basic_month', test_plan_name: 'Basic' },
      });
      stubSync({ refresh: 'failed', orgs: 'resolve' });
      wrapper = await mountModal();

      await planButton(wrapper, 'Basic').trigger('click');
      await flushPromises();

      expect(errorText(wrapper)).toBe('web.colonel.activateTestModeRefreshFailed');
      expect(wrapper.emitted('close')).toBeFalsy();
      expect(useBootstrapStore().entitlement_preview_planid).toBe('basic_month');
      expect(cancelButton(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('reports the override failure and leaves preview state untouched when the POST fails', async () => {
      apiPostMock.mockRejectedValue(new Error('500'));
      stubSync({ refresh: 'applied', orgs: 'resolve' });
      wrapper = await mountModal();

      await planButton(wrapper, 'Basic').trigger('click');
      await flushPromises();

      expect(errorText(wrapper)).toBe('web.colonel.activateTestModeFailed');
      expect(wrapper.emitted('close')).toBeFalsy();

      const bootstrap = useBootstrapStore();
      expect(bootstrap.entitlement_preview_planid).toBeUndefined();
      expect(wrapper.text()).not.toContain('web.colonel.previewModeActive');
      // No refresh is attempted for an override that never landed.
      expect(useOrganizationStore().fetchOrganizations).not.toHaveBeenCalled();
      expect(cancelButton(wrapper).attributes('disabled')).toBeUndefined();
    });
  });

  describe('reset', () => {
    beforeEach(() => {
      useBootstrapStore().$patch({
        entitlement_preview_planid: 'pro_month',
        entitlement_preview_plan_name: 'Pro',
      } as never);
    });

    function resetButton(w: VueWrapper) {
      const b = w.findAll('button[type="button"]').find((x) => x.text() === 'web.colonel.resetToActual');
      expect(b).toBeTruthy();
      return b!;
    }

    it('reports the refresh failure, not the reset, when the refresh rejects after a successful POST', async () => {
      apiPostMock.mockResolvedValue({ data: { status: 'cleared', actual_planid: 'free_v1' } });
      stubSync({ refresh: 'applied', orgs: 'reject' });
      wrapper = await mountModal();

      await resetButton(wrapper).trigger('click');
      await flushPromises();

      expect(apiPostMock).toHaveBeenCalledWith('/api/colonel/entitlement-preview', { planid: null });
      expect(errorText(wrapper)).toBe('web.colonel.resetTestModeRefreshFailed');
      expect(wrapper.emitted('close')).toBeFalsy();

      // The reset DID apply: preview mode is no longer shown as active.
      const bootstrap = useBootstrapStore();
      expect(bootstrap.entitlement_preview_planid).toBeNull();
      expect(bootstrap.entitlement_preview_plan_name).toBeNull();
      expect(wrapper.text()).not.toContain('web.colonel.previewModeActive');
      expect(cancelButton(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('reports the reset failure and keeps preview mode active when the POST fails', async () => {
      apiPostMock.mockRejectedValue(new Error('500'));
      stubSync({ refresh: 'applied', orgs: 'resolve' });
      wrapper = await mountModal();

      await resetButton(wrapper).trigger('click');
      await flushPromises();

      expect(errorText(wrapper)).toBe('web.colonel.resetTestModeFailed');
      expect(wrapper.emitted('close')).toBeFalsy();
      expect(useBootstrapStore().entitlement_preview_planid).toBe('pro_month');
      expect(wrapper.text()).toContain('web.colonel.previewModeActive');
      expect(resetButton(wrapper).attributes('disabled')).toBeUndefined();
    });
  });
});
