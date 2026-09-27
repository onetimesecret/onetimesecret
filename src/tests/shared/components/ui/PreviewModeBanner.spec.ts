// src/tests/shared/components/ui/PreviewModeBanner.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The banner's reset POSTs /api/colonel/entitlement-preview, the same
 * protected endpoint PlanPreviewModal submits to. ADR-046#authority-action-gating
 * applies to both: while authority is not established (or the session is
 * stale) the control is disabled and the handler refuses to POST.
 */

const apiPostMock = vi.fn();
vi.mock('@/api', () => ({
  createApi: () => ({
    post: (...args: unknown[]) => apiPostMock(...args),
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import PreviewModeBanner from '@/shared/components/ui/PreviewModeBanner.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

describe('PreviewModeBanner — reset gating (ADR-046#authority-action-gating)', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
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

  async function mountBanner(): Promise<VueWrapper> {
    const authStore = useAuthStore();
    // The post-reset refresh is outside this spec's scope.
    vi.spyOn(authStore, 'refresh').mockResolvedValue(undefined as never);
    const w = mount(PreviewModeBanner, { global: { plugins: [i18n] } });
    await flushPromises();
    return w;
  }

  const resetButton = (w: VueWrapper) => w.get('button[type="button"]');

  it('reset is enabled and POSTs when authority is established (authenticated)', async () => {
    seed('authenticated');
    wrapper = await mountBanner();

    expect(resetButton(wrapper).attributes('disabled')).toBeUndefined();
    await resetButton(wrapper).trigger('click');
    await flushPromises();

    expect(apiPostMock).toHaveBeenCalledWith('/api/colonel/entitlement-preview', {
      planid: null,
    });
  });

  it.each(['unavailable', 'checking'] as const)(
    'reset is disabled and does not POST when authStatus is %s',
    async (status) => {
      seed(status);
      wrapper = await mountBanner();

      expect(resetButton(wrapper).attributes('disabled')).toBeDefined();
      await resetButton(wrapper).trigger('click');
      await flushPromises();

      expect(apiPostMock).not.toHaveBeenCalled();
    }
  );

  it('reset is disabled and does not POST in stale-session mode', async () => {
    seed('authenticated');
    wrapper = await mountBanner();
    useAuthStore().staleSession = true;
    await flushPromises();

    expect(resetButton(wrapper).attributes('disabled')).toBeDefined();
    await resetButton(wrapper).trigger('click');
    await flushPromises();

    expect(apiPostMock).not.toHaveBeenCalled();
  });

  it('the handler refuses to POST even if the disabled attribute is bypassed', async () => {
    seed('unavailable');
    wrapper = await mountBanner();

    // Drive the handler directly: a click on a disabled button is swallowed
    // by the DOM, so the attribute test alone does not prove the guard.
    const button = resetButton(wrapper).element as HTMLButtonElement;
    button.disabled = false;
    button.click();
    await flushPromises();

    expect(apiPostMock).not.toHaveBeenCalled();
  });
});
