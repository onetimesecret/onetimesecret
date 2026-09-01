// src/tests/apps/admin/ElevationBanner.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The one banner mounted in AdminLayout, in both of its states.
 *
 * #4327 — a live step-up window counts down here, and NOTHING renders when no
 * window is open (a permanent "you are not elevated" bar would train operators
 * to ignore the bar that matters).
 *
 * #4331 — the expired-admin-session notice. The server bounds /api/colonel but
 * deliberately does NOT gate the /colonel shell, so the SPA loads on a stale
 * session and this banner is where the operator learns why nothing works. It
 * WINS over every elevation state: an elevation window is meaningless once the
 * surface itself refuses the session.
 *
 * The other load-bearing property asserted here is the absence of a timer that
 * makes a request: the countdown is local, so an idle admin tab issues no HTTP.
 * A poll would refresh the server-side activity clock the #4331 idle bound reads
 * and silently disable a shipped security control.
 */

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

import ElevationBanner from '@/apps/admin/components/ElevationBanner.vue';
import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import {
  ADMIN_SESSION_EXPIRED_PREFIX,
  noteAdminSessionExpiry,
} from '@/apps/admin/utils/adminSessionExpiry';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function statusPayload(record: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: { elevated: false, expires_at: null, seconds_remaining: 0, ...record },
    details: {
      enabled: true,
      window: 600,
      reauth_grace: 0,
      grace_available: false,
      password_available: true,
      factors: ['password'],
    },
  };
}

/** An Axios 401 carrying the server's admin-session-expired marker. */
function expiredError(reason = 'absolute'): AxiosError {
  const error = new AxiosError('Request failed with status code 401');
  error.response = {
    status: 401,
    statusText: 'Unauthorized',
    headers: {},
    config: {} as never,
    data: {
      error: 'Authentication Required',
      message: `${ADMIN_SESSION_EXPIRED_PREFIX} Admin session ${reason} timeout exceeded; sign in again`,
    },
  };
  return error;
}

describe('ElevationBanner', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    __resetColonelElevationState();
  });

  afterEach(() => {
    wrapper?.unmount();
    __resetColonelElevationState();
  });

  async function mountWith(record: Record<string, unknown> = {}): Promise<void> {
    mockApi.get.mockResolvedValue({ data: statusPayload(record) });
    wrapper = mount(ElevationBanner, { global: { plugins: [i18n] } });
    await flushPromises();
  }

  describe('the elevation states (#4327)', () => {
    it('renders nothing when no window is open', async () => {
      await mountWith();

      expect(wrapper.find('[data-testid="elevation-banner"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="admin-session-expired-banner"]').exists()).toBe(false);
    });

    it('renders the countdown while a window is live', async () => {
      await mountWith({ elevated: true, expires_at: 1_700_000_600, seconds_remaining: 305 });

      // i18n is pass-through in these specs, so the interpolated mm:ss does not
      // land in the rendered text — assert on the key instead.
      const banner = wrapper.find('[data-testid="elevation-banner"]');
      expect(banner.exists()).toBe(true);
      expect(banner.text()).toContain('web.admin.elevation.banner.active');
    });
  });

  describe('the expired state (#4331)', () => {
    it('renders the notice with a session-clearing recovery control once a 401 carries the marker', async () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true });
      vi.stubGlobal('fetch', fetchMock);
      const originalLocation = window.location;
      const assignMock = vi.fn();
      Object.defineProperty(window, 'location', {
        value: { assign: assignMock },
        writable: true,
        configurable: true,
      });

      try {
        await mountWith();
        expect(wrapper.find('[data-testid="admin-session-expired-banner"]').exists()).toBe(false);

        noteAdminSessionExpiry(expiredError('idle'));
        await flushPromises();

        const banner = wrapper.find('[data-testid="admin-session-expired-banner"]');
        expect(banner.exists()).toBe(true);
        expect(banner.text()).toContain('web.admin.session.expired');

        // The recovery affordance is an ACTION, not a bare link: a /signin link
        // no-ops in simple mode while the cookie still reads authenticated, so
        // clicking it clears the session first, then navigates (#4331).
        const signin = wrapper.find('[data-testid="admin-session-signin"]');
        expect(signin.exists()).toBe(true);
        await signin.trigger('click');
        await flushPromises();

        expect(fetchMock).toHaveBeenCalledWith(
          '/auth/logout',
          expect.objectContaining({ method: 'GET' })
        );
        expect(assignMock).toHaveBeenCalledWith('/signin?redirect=/colonel');
      } finally {
        Object.defineProperty(window, 'location', {
          value: originalLocation,
          writable: true,
          configurable: true,
        });
        vi.unstubAllGlobals();
      }
    });

    // Priority, both ways round: an operator with a live sudo window whose admin
    // surface has expired must see the reason nothing works, not a countdown
    // that no longer buys them anything.
    it('WINS over a live elevation window', async () => {
      await mountWith({ elevated: true, expires_at: 1_700_000_600, seconds_remaining: 305 });
      expect(wrapper.find('[data-testid="elevation-banner"]').exists()).toBe(true);

      noteAdminSessionExpiry(expiredError());
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-session-expired-banner"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="elevation-banner"]').exists()).toBe(false);
    });

    it('WINS over a recent_auth window too', async () => {
      await mountWith({ elevated: true, expires_at: 1_700_000_600, seconds_remaining: 305 });
      useColonelElevation().activeFactor.value = 'recent_auth';
      await flushPromises();
      expect(wrapper.find('[data-testid="elevation-banner"]').exists()).toBe(true);

      noteAdminSessionExpiry(expiredError());
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-session-expired-banner"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="elevation-banner"]').exists()).toBe(false);
    });

    // The composable's own catch is what discovers the expiry on a stale tab:
    // refresh() is the first request the console makes on entry.
    it('is raised by the status fetch the banner itself makes on mount', async () => {
      mockApi.get.mockRejectedValue(expiredError());
      wrapper = mount(ElevationBanner, { global: { plugins: [i18n] } });
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-session-expired-banner"]').exists()).toBe(true);
    });

    it('ignores a 401 that is not an expired admin window', async () => {
      await mountWith();

      const other = new AxiosError('Request failed with status code 401');
      other.response = {
        status: 401,
        statusText: 'Unauthorized',
        headers: {},
        config: {} as never,
        data: { error: 'Authentication Required', message: '[SESSION_NOT_AUTHENTICATED]' },
      };
      expect(noteAdminSessionExpiry(other)).toBe(false);
      await flushPromises();

      expect(wrapper.find('[data-testid="admin-session-expired-banner"]').exists()).toBe(false);
    });
  });

  // #4331's idle bound only bites because nothing here polls.
  it('makes exactly ONE request for the life of the banner', async () => {
    await mountWith({ elevated: true, expires_at: 1_700_000_600, seconds_remaining: 305 });
    const calls = mockApi.get.mock.calls.length;

    vi.useFakeTimers();
    vi.advanceTimersByTime(60_000);
    vi.useRealTimers();
    await flushPromises();

    expect(mockApi.get.mock.calls.length).toBe(calls);
  });
});
