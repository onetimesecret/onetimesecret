// src/tests/apps/admin/ElevationPrompt.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The step-up (sudo) prompt (#4327).
 *
 * The property under test is the one the security review's B-3 finding turns
 * on: the prompt NEVER elevates without an explicit operator gesture. The
 * rejected first draft called `elevate('recent_auth')` silently on open, which
 * made step-up a no-op for the first N seconds after every colonel sign-in.
 *
 * Three forks, decided by what the SERVER says this account can do:
 *   1. password holder      → the shared password modal;
 *   2. SSO-only + a grace   → one deliberate "confirm it's me" click;
 *   3. SSO-only, no grace   → the remediation, and no input at all.
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

vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" @close="$emit(\'close\')"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: { name: 'DialogPanel', template: '<div class="dialog-panel"><slot /></div>', props: ['class'] },
  DialogTitle: { name: 'DialogTitle', template: '<h3><slot /></h3>', props: ['as', 'class'] },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: { name: 'TransitionChild', template: '<div><slot /></div>', props: ['as'] },
}));

import ElevationPrompt from '@/apps/admin/components/ElevationPrompt.vue';
import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

function statusPayload(details: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: { elevated: false, expires_at: null, seconds_remaining: 0 },
    details: {
      enabled: true,
      window: 600,
      reauth_grace: 0,
      grace_available: false,
      password_available: true,
      factors: ['password'],
      ...details,
    },
  };
}

function grantPayload(factor = 'password') {
  return {
    shrimp: '',
    record: { elevated: true, expires_at: 1_700_000_600, seconds_remaining: 600 },
    details: { factor, window: 600 },
  };
}

describe('ElevationPrompt', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    __resetColonelElevationState();
  });

  afterEach(() => {
    wrapper?.unmount();
    __resetColonelElevationState();
  });

  async function mountWith(details: Record<string, unknown> = {}): Promise<void> {
    mockApi.get.mockResolvedValue({ data: statusPayload(details) });
    wrapper = mount(ElevationPrompt, { global: { plugins: [i18n] } });
    // Seed the per-account capability before anything opens the prompt.
    await useColonelElevation().refresh();
    await flushPromises();
  }

  it('renders nothing while closed', async () => {
    await mountWith();

    expect(wrapper.find('[data-testid="elevation-prompt-alt"]').exists()).toBe(false);
    expect(wrapper.html()).not.toContain('elevation-confirm-its-you');
  });

  describe('password fork (the normal case)', () => {
    it('elevates with the typed password and resolves the pending request', async () => {
      await mountWith();
      mockApi.post.mockResolvedValue({ data: grantPayload() });

      const elevation = useColonelElevation();
      const pending = elevation.requestElevation();
      await flushPromises();

      // The shared modal owns the input; drive its emit directly.
      const modal = wrapper.findComponent({ name: 'PasswordConfirmModal' });
      expect(modal.exists()).toBe(true);
      modal.vm.$emit('confirm', 'hunter2');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/elevation', {
        factor: 'password',
        password: 'hunter2',
      });
      await expect(pending).resolves.toBe(true);
    });

    it('keeps the prompt open and resolves nothing when the password is wrong', async () => {
      await mountWith();
      // A real AxiosError, so the shared classifier extracts `data.error` —
      // the server's remediation message is the whole point of showing it.
      const rejection = new AxiosError('Request failed');
      rejection.response = {
        status: 403,
        data: { error: 'Password verification failed.', error_code: 'elevation_failed' },
        statusText: '',
        headers: {},
        config: {} as never,
      };
      mockApi.post.mockRejectedValue(rejection);

      const elevation = useColonelElevation();
      void elevation.requestElevation();
      await flushPromises();

      wrapper.findComponent({ name: 'PasswordConfirmModal' }).vm.$emit('confirm', 'wrong');
      await flushPromises();

      expect(elevation.promptOpen.value).toBe(true);
      expect(elevation.error.value).toBe('Password verification failed.');
    });

    it('resolves false on cancel and elevates nothing', async () => {
      await mountWith();

      const elevation = useColonelElevation();
      const pending = elevation.requestElevation();
      await flushPromises();

      wrapper.findComponent({ name: 'PasswordConfirmModal' }).vm.$emit('cancel');
      await flushPromises();

      await expect(pending).resolves.toBe(false);
      expect(mockApi.post).not.toHaveBeenCalled();
    });
  });

  describe('recent_auth fork (SSO-only account, grace configured)', () => {
    const details = {
      password_available: false,
      reauth_grace: 300,
      grace_available: true,
      factors: ['password', 'recent_auth'],
    };

    // The B-3 regression guard, on the client side.
    it('does NOT elevate on open — it waits for a click', async () => {
      await mountWith(details);

      void useColonelElevation().requestElevation();
      await flushPromises();

      expect(wrapper.find('[data-testid="elevation-confirm-its-you"]').exists()).toBe(true);
      expect(mockApi.post).not.toHaveBeenCalled();
    });

    it('elevates on the deliberate click', async () => {
      await mountWith(details);
      mockApi.post.mockResolvedValue({ data: grantPayload('recent_auth') });

      const pending = useColonelElevation().requestElevation();
      await flushPromises();

      await wrapper.find('[data-testid="elevation-confirm-its-you"]').trigger('click');
      await flushPromises();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/elevation', {
        factor: 'recent_auth',
        password: '',
      });
      await expect(pending).resolves.toBe(true);
    });
  });

  describe('unsatisfiable fork (SSO-only account, no grace)', () => {
    const details = { password_available: false, factors: ['password'] };

    it('renders the remediation and NO input', async () => {
      await mountWith(details);

      void useColonelElevation().requestElevation();
      await flushPromises();

      expect(wrapper.find('[data-testid="elevation-prompt-unsatisfiable"]').exists()).toBe(true);
      expect(wrapper.find('input').exists()).toBe(false);
      expect(wrapper.find('[data-testid="elevation-confirm-its-you"]').exists()).toBe(false);
      expect(wrapper.findComponent({ name: 'PasswordConfirmModal' }).exists()).toBe(false);
    });

    it('closes without elevating', async () => {
      await mountWith(details);

      const pending = useColonelElevation().requestElevation();
      await flushPromises();

      await wrapper.find('button').trigger('click');
      await flushPromises();

      await expect(pending).resolves.toBe(false);
      expect(mockApi.post).not.toHaveBeenCalled();
    });
  });
});
