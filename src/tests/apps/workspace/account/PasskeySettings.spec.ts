// src/tests/apps/workspace/account/PasskeySettings.spec.ts

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import { createTestI18n } from '@tests/setup';
import PasskeySettings from '@/apps/workspace/account/PasskeySettings.vue';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/account/settings/security/passkeys' })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  isNavigationFailure: () => false,
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock SettingsLayout
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: {
    name: 'SettingsLayout',
    template: '<div class="mock-settings-layout"><slot /></div>',
  },
}));

// Mock ListSkeleton (loading indicator)
vi.mock('@/shared/components/closet/ListSkeleton.vue', () => ({
  default: {
    name: 'ListSkeleton',
    template: '<div data-testid="list-skeleton"></div>',
  },
}));

// Stub PasswordConfirmModal — the real one wraps Headless UI Dialog/transitions.
// The stub emits confirm with a fixed password so flows can be exercised.
vi.mock('@/shared/components/modals/PasswordConfirmModal.vue', () => ({
  default: {
    name: 'PasswordConfirmModal',
    props: ['open', 'title', 'description', 'loading', 'error', 'variant'],
    emits: ['update:open', 'confirm', 'cancel'],
    template: `
      <div v-if="open" data-testid="password-confirm-modal">
        <p data-testid="modal-title">{{ title }}</p>
        <p data-testid="modal-description">{{ description }}</p>
        <p v-if="error" data-testid="modal-error">{{ error }}</p>
        <button data-testid="modal-confirm" type="button" @click="$emit('confirm', 'hunter2')">confirm</button>
        <button data-testid="modal-cancel" type="button" @click="$emit('cancel')">cancel</button>
      </div>`,
  },
}));

// Stub ConfirmDialog (no-password removal path)
vi.mock('@/shared/components/modals/ConfirmDialog.vue', () => ({
  default: {
    name: 'ConfirmDialog',
    props: ['title', 'message', 'confirmText', 'cancelText', 'type'],
    emits: ['confirm', 'cancel'],
    template: `
      <div data-testid="confirm-dialog">
        <p data-testid="confirm-dialog-message">{{ message }}</p>
        <button data-testid="confirm-dialog-confirm" type="button" @click="$emit('confirm')">confirm</button>
        <button data-testid="confirm-dialog-cancel" type="button" @click="$emit('cancel')">cancel</button>
      </div>`,
  },
}));

// Mock useWebAuthn composable
const mockWebAuthnState = {
  supported: ref(true),
  isLoading: ref(false),
  error: ref<string | null>(null),
  registerWebAuthn: vi.fn(),
  fetchWebAuthnCredentials: vi.fn(),
  removeWebAuthn: vi.fn(),
  clearError: vi.fn(),
};

vi.mock('@/shared/composables/useWebAuthn', () => ({
  useWebAuthn: () => mockWebAuthnState,
}));

const i18n = createTestI18n();

const sampleCredentials = () => [
  { id: 'credential-aaa-a1b2c3', last_used_at: '2026-08-01T12:00:00Z' },
  { id: 'credential-bbb-d4e5f6', last_used_at: null },
];

/**
 * PasskeySettings Component Tests
 *
 * Mounts the REAL component (no inline stub). createTestI18n is pass-through
 * (ADR-014): t() renders keys as-is, so assertions target i18n keys.
 *
 * Covers:
 * - Passkey list rendering from fetchWebAuthnCredentials (id suffix + last used)
 * - Empty and loading states
 * - Register flow via PasswordConfirmModal (has_password: true)
 * - Register flow skipping the modal (has_password: false, SSO-only)
 * - Remove flow via PasswordConfirmModal / ConfirmDialog per has_password
 * - Refresh-after-register and refresh-after-remove
 * - Error surfaces, browser support, benefits, related settings
 */
describe('PasskeySettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockWebAuthnState.supported.value = true;
    mockWebAuthnState.isLoading.value = false;
    mockWebAuthnState.error.value = null;
    mockWebAuthnState.registerWebAuthn.mockResolvedValue(true);
    mockWebAuthnState.fetchWebAuthnCredentials.mockResolvedValue([]);
    mockWebAuthnState.removeWebAuthn.mockResolvedValue(true);
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  // has_password comes from the bootstrap store (synchronously available at
  // mount) — seed it via Pinia initialState rather than mocking a composable.
  const mountComponent = (hasPassword = true) =>
    mount(PasskeySettings, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: { has_password: hasPassword },
            },
          }),
        ],
      },
    });

  const mountSettled = async (hasPassword = true) => {
    const w = mountComponent(hasPassword);
    await flushPromises();
    return w;
  };

  const findAddButton = (w: VueWrapper) =>
    w.findAll('button').find((b) => b.text().includes('web.auth.passkeys.add_passkey'));

  const findRemoveButtons = (w: VueWrapper) =>
    w.findAll('button').filter((b) => b.text().includes('web.auth.passkeys.remove_passkey'));

  describe('Basic Rendering', () => {
    it('renders within SettingsLayout', async () => {
      wrapper = await mountSettled();

      expect(wrapper.find('.mock-settings-layout').exists()).toBe(true);
    });

    it('renders page title and description', async () => {
      wrapper = await mountSettled();

      const title = wrapper.find('h1');
      expect(title.exists()).toBe(true);
      expect(title.text()).toBe('web.auth.passkeys.title');
      expect(wrapper.text()).toContain('web.auth.passkeys.setup_description');
    });

    it('renders add passkey button when supported', async () => {
      wrapper = await mountSettled();

      expect(findAddButton(wrapper)).toBeDefined();
    });

    it('fetches the passkey list on mount', async () => {
      wrapper = await mountSettled();

      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(1);
    });
  });

  describe('Browser Support Detection', () => {
    it('shows unsupported warning when WebAuthn is not supported', async () => {
      mockWebAuthnState.supported.value = false;
      wrapper = await mountSettled();

      const warning = wrapper.find('[role="alert"]');
      expect(warning.exists()).toBe(true);
      expect(warning.text()).toContain('web.auth.webauthn.notSupported');
      expect(warning.text()).toContain('web.auth.webauthn.requiresModernBrowser');
    });

    it('hides add passkey button when not supported', async () => {
      mockWebAuthnState.supported.value = false;
      wrapper = await mountSettled();

      expect(findAddButton(wrapper)).toBeUndefined();
    });
  });

  describe('Passkey List', () => {
    it('shows the loading skeleton while credentials are being fetched', async () => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockImplementation(
        () => new Promise(() => {}) // never resolves
      );
      wrapper = mountComponent();
      await wrapper.vm.$nextTick();

      expect(wrapper.find('[data-testid="list-skeleton"]').exists()).toBe(true);
    });

    it('renders one row per credential with a generic name and id suffix', async () => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockResolvedValue(sampleCredentials());
      wrapper = await mountSettled();

      expect(wrapper.text()).toContain('web.auth.passkeys.name');
      expect(wrapper.text()).toContain('#a1b2c3');
      expect(wrapper.text()).toContain('#d4e5f6');
      expect(findRemoveButtons(wrapper)).toHaveLength(2);
      expect(wrapper.text()).not.toContain('web.auth.passkeys.no_passkeys_description');
    });

    it('shows last-used for used credentials and never-used for null', async () => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockResolvedValue(sampleCredentials());
      wrapper = await mountSettled();

      // Pass-through i18n renders the key for the parameterized last_used string
      expect(wrapper.text()).toContain('web.auth.passkeys.last_used');
      expect(wrapper.text()).toContain('web.auth.passkeys.never_used');
    });

    it('does not render a created date (credentials have none)', async () => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockResolvedValue(sampleCredentials());
      wrapper = await mountSettled();

      expect(wrapper.text()).not.toContain('web.auth.passkeys.created');
    });

    it('shows the empty state when no passkeys exist', async () => {
      wrapper = await mountSettled();

      expect(wrapper.text()).toContain('web.auth.passkeys.no_passkeys');
      expect(wrapper.text()).toContain('web.auth.passkeys.no_passkeys_description');
    });

    it('surfaces a fetch error and keeps the empty state', async () => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockImplementation(async () => {
        mockWebAuthnState.error.value = 'web.auth.passkeys.load_failed';
        return null;
      });
      wrapper = await mountSettled();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.auth.passkeys.load_failed');
      expect(wrapper.text()).toContain('web.auth.passkeys.no_passkeys');
    });
  });

  describe('Add Passkey (account with password)', () => {
    it('opens the password modal instead of registering directly', async () => {
      wrapper = await mountSettled();

      await findAddButton(wrapper)!.trigger('click');

      const modal = wrapper.find('[data-testid="password-confirm-modal"]');
      expect(modal.exists()).toBe(true);
      expect(modal.find('[data-testid="modal-description"]').text()).toBe(
        'web.COMMON.password_required_for_action'
      );
      expect(mockWebAuthnState.registerWebAuthn).not.toHaveBeenCalled();
    });

    it('registers with the confirmed password and refreshes the list', async () => {
      wrapper = await mountSettled();

      await findAddButton(wrapper)!.trigger('click');
      await wrapper.find('[data-testid="modal-confirm"]').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.registerWebAuthn).toHaveBeenCalledWith('hunter2');
      expect(wrapper.text()).toContain('web.auth.passkeys.registered_success');
      // Mount + refresh after successful registration
      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-testid="password-confirm-modal"]').exists()).toBe(false);
    });

    it('keeps the modal open and shows the error on failure', async () => {
      mockWebAuthnState.registerWebAuthn.mockImplementation(async () => {
        mockWebAuthnState.error.value = 'Wrong password';
        return false;
      });
      wrapper = await mountSettled();

      await findAddButton(wrapper)!.trigger('click');
      await wrapper.find('[data-testid="modal-confirm"]').trigger('click');
      await flushPromises();

      const modal = wrapper.find('[data-testid="password-confirm-modal"]');
      expect(modal.exists()).toBe(true);
      expect(modal.find('[data-testid="modal-error"]').text()).toBe('Wrong password');
      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(1);
    });
  });

  describe('Add Passkey (SSO-only account, no password)', () => {
    it('registers directly without opening the password modal', async () => {
      wrapper = await mountSettled(false);

      await findAddButton(wrapper)!.trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="password-confirm-modal"]').exists()).toBe(false);
      expect(mockWebAuthnState.registerWebAuthn).toHaveBeenCalledTimes(1);
      expect(mockWebAuthnState.registerWebAuthn.mock.calls[0][0]).toBeUndefined();
    });

    it('shows success and refreshes the list after registering', async () => {
      wrapper = await mountSettled(false);

      await findAddButton(wrapper)!.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('web.auth.passkeys.registered_success');
      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(2);
    });

    it('surfaces a registration error inline (no modal to sync to)', async () => {
      mockWebAuthnState.registerWebAuthn.mockImplementation(async () => {
        mockWebAuthnState.error.value = 'web.auth.webauthn.cancelled';
        return false;
      });
      wrapper = await mountSettled(false);

      await findAddButton(wrapper)!.trigger('click');
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.auth.webauthn.cancelled');
      expect(wrapper.text()).not.toContain('web.auth.passkeys.registered_success');
    });
  });

  describe('Remove Passkey (account with password)', () => {
    beforeEach(() => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockResolvedValue(sampleCredentials());
    });

    it('opens the danger password modal with the confirm-remove message', async () => {
      wrapper = await mountSettled();

      await findRemoveButtons(wrapper)[0].trigger('click');

      const modal = wrapper.find('[data-testid="password-confirm-modal"]');
      expect(modal.exists()).toBe(true);
      expect(modal.find('[data-testid="modal-title"]').text()).toBe(
        'web.auth.passkeys.remove_passkey'
      );
      expect(modal.find('[data-testid="modal-description"]').text()).toBe(
        'web.auth.passkeys.confirm_remove'
      );
      expect(mockWebAuthnState.removeWebAuthn).not.toHaveBeenCalled();
    });

    it('removes with the confirmed password and refreshes the list', async () => {
      wrapper = await mountSettled();

      await findRemoveButtons(wrapper)[0].trigger('click');
      await wrapper.find('[data-testid="modal-confirm"]').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.removeWebAuthn).toHaveBeenCalledWith(
        'credential-aaa-a1b2c3',
        'hunter2'
      );
      expect(wrapper.text()).toContain('web.auth.passkeys.removed_success');
      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-testid="password-confirm-modal"]').exists()).toBe(false);
    });

    it('keeps the modal open and shows the error on failure', async () => {
      mockWebAuthnState.removeWebAuthn.mockImplementation(async () => {
        mockWebAuthnState.error.value = 'invalid password';
        return false;
      });
      wrapper = await mountSettled();

      await findRemoveButtons(wrapper)[0].trigger('click');
      await wrapper.find('[data-testid="modal-confirm"]').trigger('click');
      await flushPromises();

      const modal = wrapper.find('[data-testid="password-confirm-modal"]');
      expect(modal.exists()).toBe(true);
      expect(modal.find('[data-testid="modal-error"]').text()).toBe('invalid password');
      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(1);
    });

    it('does not remove when the modal is cancelled', async () => {
      wrapper = await mountSettled();

      await findRemoveButtons(wrapper)[0].trigger('click');
      await wrapper.find('[data-testid="modal-cancel"]').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.removeWebAuthn).not.toHaveBeenCalled();
    });
  });

  describe('Remove Passkey (SSO-only account, no password)', () => {
    beforeEach(() => {
      mockWebAuthnState.fetchWebAuthnCredentials.mockResolvedValue(sampleCredentials());
    });

    it('opens a plain confirm dialog instead of the password modal', async () => {
      wrapper = await mountSettled(false);

      await findRemoveButtons(wrapper)[0].trigger('click');

      expect(wrapper.find('[data-testid="password-confirm-modal"]').exists()).toBe(false);
      const dialog = wrapper.find('[data-testid="confirm-dialog"]');
      expect(dialog.exists()).toBe(true);
      expect(dialog.find('[data-testid="confirm-dialog-message"]').text()).toBe(
        'web.auth.passkeys.confirm_remove'
      );
    });

    it('removes without a password on confirm and refreshes the list', async () => {
      wrapper = await mountSettled(false);

      await findRemoveButtons(wrapper)[1].trigger('click');
      await wrapper.find('[data-testid="confirm-dialog-confirm"]').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.removeWebAuthn).toHaveBeenCalledTimes(1);
      expect(mockWebAuthnState.removeWebAuthn.mock.calls[0][0]).toBe('credential-bbb-d4e5f6');
      expect(mockWebAuthnState.removeWebAuthn.mock.calls[0][1]).toBeUndefined();
      expect(wrapper.text()).toContain('web.auth.passkeys.removed_success');
      expect(mockWebAuthnState.fetchWebAuthnCredentials).toHaveBeenCalledTimes(2);
    });

    it('does not remove when the dialog is cancelled', async () => {
      wrapper = await mountSettled(false);

      await findRemoveButtons(wrapper)[0].trigger('click');
      await wrapper.find('[data-testid="confirm-dialog-cancel"]').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.removeWebAuthn).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
    });
  });

  describe('Benefits Section', () => {
    it('displays all benefit items', async () => {
      wrapper = await mountSettled();

      expect(wrapper.text()).toContain('web.LABELS.benefits');
      expect(wrapper.text()).toContain('web.auth.passkeys.benefit_secure');
      expect(wrapper.text()).toContain('web.auth.passkeys.benefit_fast');
      expect(wrapper.text()).toContain('web.auth.passkeys.benefit_synced');
    });
  });

  describe('Related Settings', () => {
    // vue-router-mock (setupRouter.ts) stubs router-link as an empty
    // <router-link-stub> element that keeps the `to` attribute but renders no
    // slot content — so only the target route is assertable.
    it('links to MFA settings', async () => {
      wrapper = await mountSettled();

      expect(
        wrapper.find('router-link-stub[to="/account/settings/security/mfa"]').exists()
      ).toBe(true);
    });

    it('links to recovery codes settings', async () => {
      wrapper = await mountSettled();

      expect(
        wrapper
          .find('router-link-stub[to="/account/settings/security/recovery-codes"]')
          .exists()
      ).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('page title is h1 and section title is h2', async () => {
      wrapper = await mountSettled();

      expect(wrapper.find('h1').text()).toBe('web.auth.passkeys.title');
      expect(wrapper.find('h2').text()).toBe('web.auth.passkeys.title');
    });

    it('message dismiss buttons have accessible labels', async () => {
      mockWebAuthnState.error.value = 'Some error';
      wrapper = await mountSettled();

      const dismiss = wrapper.find('button[aria-label="Dismiss"]');
      expect(dismiss.exists()).toBe(true);
    });
  });
});
