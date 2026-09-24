// src/tests/shared/components/ImpersonationBanner.spec.ts

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The impersonation banner is a SAFETY CONTROL: it is the only on-screen
 * evidence that the identity being rendered is borrowed, and the only way out
 * of the session. These tests pin the three properties that matter —
 * it renders from SERVER state only, it counts down to the server's deadline,
 * and stopping leaves the SPA rather than soft-navigating inside it.
 */

const stopImpersonationMock = vi.fn();
vi.mock('@/services/impersonation.service', () => ({
  IMPERSONATION_STOP_FALLBACK_PATH: '/colonel',
  IMPERSONATION_STOP_PATH: '/api/account/impersonation/stop',
  stopImpersonation: (...args: unknown[]) => stopImpersonationMock(...args),
}));

const hardNavigateMock = vi.fn();
vi.mock('@/utils/navigation', () => ({
  hardNavigate: (...args: unknown[]) => hardNavigateMock(...args),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size', 'aria-label'],
  },
}));

import ImpersonationBanner from '@/shared/components/ui/ImpersonationBanner.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

/** Fixed wall clock so the countdown arithmetic is deterministic. */
const NOW_MS = 1_756_700_000_000;

function marker(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    impersonation_id: 'imp_abc123',
    impersonator_extid: 'ur_colonel',
    target_extid: 'ur_bob',
    target_email: 'bob@example.com',
    started_at: NOW_MS / 1000,
    expires_at: NOW_MS / 1000 + 125, // 2:05
    ...overrides,
  };
}

describe('ImpersonationBanner', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(NOW_MS);
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
    vi.useRealTimers();
  });

  /** Seed the SERVER-derived marker and mount. */
  function mountBanner(state: Record<string, unknown> | null): VueWrapper {
    const store = useBootstrapStore();
    store.$patch({ impersonation: state as never });
    return mount(ImpersonationBanner, { global: { plugins: [i18n] } });
  }

  const banner = (w: VueWrapper) => w.find('[data-testid="impersonation-banner"]');
  const countdown = (w: VueWrapper) => w.find('[data-testid="impersonation-countdown"]');
  const stopButton = (w: VueWrapper) => w.find('[data-testid="impersonation-stop"]');

  describe('rendering from bootstrap state', () => {
    it('renders nothing when no impersonation is active', () => {
      wrapper = mountBanner(null);
      expect(banner(wrapper).exists()).toBe(false);
    });

    it('announces itself, names the target, and states the read-only rule', () => {
      wrapper = mountBanner(marker());

      const el = banner(wrapper);
      expect(el.exists()).toBe(true);
      // role="status" — the notice is announced when it appears.
      expect(el.attributes('role')).toBe('status');
      expect(wrapper.find('[data-testid="impersonation-target"]').text()).toContain(
        'web.impersonation.banner.viewingAs'
      );
      expect(el.text()).toContain('web.impersonation.banner.readOnly');
      expect(el.text()).toContain('web.impersonation.banner.label');
    });

    it('exposes the target email for interpolation', () => {
      wrapper = mountBanner(marker());
      // Pass-through i18n renders keys, so assert the interpolated ARG instead.
      const vm = wrapper.vm as unknown as { impersonation: { target_email: string } };
      expect(vm.impersonation.target_email).toBe('bob@example.com');
    });

    it('disappears when the marker is cleared (stop/expiry re-read)', async () => {
      wrapper = mountBanner(marker());
      expect(banner(wrapper).exists()).toBe(true);

      useBootstrapStore().$patch({ impersonation: null });
      await flushPromises();

      expect(banner(wrapper).exists()).toBe(false);
    });
  });

  describe('countdown', () => {
    it('renders m:ss remaining and ticks down once a second', async () => {
      wrapper = mountBanner(marker());
      // The pass-through test i18n (ADR-014) renders the KEY and drops the
      // interpolated arg, so the rendered value is asserted via the
      // data-remaining hook the template binds alongside it.
      expect(countdown(wrapper).text()).toContain('web.impersonation.banner.expiresIn');
      expect(countdown(wrapper).attributes('data-remaining')).toBe('2:05');

      vi.advanceTimersByTime(60_000);
      await flushPromises();
      expect(countdown(wrapper).attributes('data-remaining')).toBe('1:05');

      vi.advanceTimersByTime(60_000);
      await flushPromises();
      expect(countdown(wrapper).attributes('data-remaining')).toBe('0:05');
    });

    it('floors at 0:00 instead of going negative, and does not navigate on its own', async () => {
      wrapper = mountBanner(marker({ expires_at: NOW_MS / 1000 + 3 }));

      vi.advanceTimersByTime(30_000);
      await flushPromises();

      expect(countdown(wrapper).attributes('data-remaining')).toBe('0:00');
      // The SERVER ends the session; a client timer must not drive navigation.
      expect(hardNavigateMock).not.toHaveBeenCalled();
    });

    it('clears its interval on unmount', () => {
      wrapper = mountBanner(marker());
      expect(vi.getTimerCount()).toBeGreaterThan(0);

      wrapper.unmount();
      wrapper = undefined;

      expect(vi.getTimerCount()).toBe(0);
    });
  });

  describe('stop', () => {
    it('POSTs the stop endpoint and HARD-navigates to the returned path', async () => {
      stopImpersonationMock.mockResolvedValue('/colonel/customers/ur_bob');
      wrapper = mountBanner(marker());

      await stopButton(wrapper).trigger('click');
      await flushPromises();

      expect(stopImpersonationMock).toHaveBeenCalledTimes(1);
      expect(hardNavigateMock).toHaveBeenCalledWith('/colonel/customers/ur_bob', '/colonel');
      expect(wrapper.find('[data-testid="impersonation-stop-error"]').exists()).toBe(false);
    });

    it('shows the in-flight label and refuses a second concurrent stop', async () => {
      let resolveStop: (path: string) => void = () => {};
      stopImpersonationMock.mockReturnValue(
        new Promise<string>((resolve) => {
          resolveStop = resolve;
        })
      );
      wrapper = mountBanner(marker());

      await stopButton(wrapper).trigger('click');
      expect(stopButton(wrapper).attributes('disabled')).toBeDefined();
      expect(stopButton(wrapper).text()).toContain('web.impersonation.banner.stopping');

      await stopButton(wrapper).trigger('click');
      expect(stopImpersonationMock).toHaveBeenCalledTimes(1);

      resolveStop('/colonel');
      await flushPromises();
    });

    it('leaves for the fallback when the session had ALREADY ended (service 404 path)', async () => {
      // stopImpersonation absorbs a 404 ("no marker to stop" — expired or
      // already cleared) and resolves the fallback, exactly as it does for a
      // 200 with no readable redirect. The banner must treat it as success:
      // navigate, no error shown.
      stopImpersonationMock.mockResolvedValue('/colonel');
      wrapper = mountBanner(marker());

      await stopButton(wrapper).trigger('click');
      await flushPromises();

      expect(hardNavigateMock).toHaveBeenCalledWith('/colonel', '/colonel');
      expect(wrapper.find('[data-testid="impersonation-stop-error"]').exists()).toBe(false);
    });

    it('keeps the operator in place and says so when the stop fails', async () => {
      // Only a REAL failure reaches the component's catch — the 404
      // already-ended case never rejects (see impersonation.service.spec).
      stopImpersonationMock.mockRejectedValue(new Error('403'));
      wrapper = mountBanner(marker());

      await stopButton(wrapper).trigger('click');
      await flushPromises();

      // The marker is presumed STILL ACTIVE: no navigation, banner stays,
      // and the button is usable again for a retry.
      expect(hardNavigateMock).not.toHaveBeenCalled();
      expect(banner(wrapper).exists()).toBe(true);
      const error = wrapper.find('[data-testid="impersonation-stop-error"]');
      expect(error.exists()).toBe(true);
      expect(error.attributes('role')).toBe('alert');
      expect(error.text()).toContain('web.impersonation.banner.stopFailed');
      expect(stopButton(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('is a real button (keyboard operable, not a click-only div)', () => {
      wrapper = mountBanner(marker());
      expect(stopButton(wrapper).element.tagName).toBe('BUTTON');
      expect(stopButton(wrapper).attributes('type')).toBe('button');
    });
  });
});
