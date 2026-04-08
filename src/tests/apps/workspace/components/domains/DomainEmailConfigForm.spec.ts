// src/tests/apps/workspace/components/domains/DomainEmailConfigForm.spec.ts
//
// Tests for DomainEmailConfigForm.vue covering:
// 1. Sender identity fields rendering
// 2. Event emissions (save, discard, delete)
// 3. Form validation (email format, required fields)
// 4. Delete confirmation flow
// 5. Accessibility attributes
//
// Custom mail sender model: users configure sender identity only.
// Provider credentials are resolved from installation-level configuration.

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import DomainEmailConfigForm from '@/apps/workspace/components/domains/DomainEmailConfigForm.vue';
import type { EmailConfigFormState } from '@/shared/composables/useEmailConfig';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="form-alerts" :data-error="error" />',
    props: ['error', 'success'],
  },
}));

// ─────────────────────────────────────────────────────────────────────────────
// i18n setup
// ─────────────────────────────────────────────────────────────────────────────

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          enabled: 'Enabled',
          are_you_sure_you_want_to_remove_this_domain: 'Are you sure you want to remove this configuration?',
          email: {
            from_name_label: 'From Name',
            from_name_placeholder: 'Acme Corp',
            from_address_label: 'From Address',
            from_address_placeholder: "noreply{'@'}example.com",
            reply_to_label: 'Reply-To Address',
            reply_to_placeholder: "support{'@'}example.com",
            config_description: 'When enabled, this domain uses its own email sender',
            discard_changes: 'Discard Changes',
            save_changes: 'Save Changes',
            disabled_notice: 'Email sending is currently disabled. Enable the feature to configure email settings.',
            test_email_title: 'Test email delivery',
            test_email_hint: 'Send a test email to yourself using the saved configuration.',
            send_test: 'Send test',
            test_email_sent: 'Test email sent successfully',
            test_email_failed: 'Failed to send test email',
            test_email_sent_to: 'Sent to {email}',
            delivered_via: 'Delivered via {provider}',
          },
        },
        COMMON: {
          remove: 'Remove',
          yes_delete: 'Yes, delete',
          word_cancel: 'Cancel',
          saving: 'Saving...',
          processing: 'Processing...',
        },
      },
    },
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// Test Fixtures
// ─────────────────────────────────────────────────────────────────────────────

const emptyFormState: EmailConfigFormState = {
  from_name: '',
  from_address: '',
  reply_to: '',
  enabled: false,
};

const configuredFormState: EmailConfigFormState = {
  from_name: 'Acme Corp',
  from_address: 'noreply@acme.com',
  reply_to: 'support@acme.com',
  enabled: true,
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('DomainEmailConfigForm', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createTestingPinia>;

  beforeEach(() => {
    pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (props: Partial<{
    formState: EmailConfigFormState;
    isConfigured: boolean;
    isSaving: boolean;
    isDeleting: boolean;
    isTesting: boolean;
    hasUnsavedChanges: boolean;
    provider: string;
    testResult: Record<string, unknown> | null;
    testError: string;
    error: string;
  }> = {}) => {
    return mount(DomainEmailConfigForm, {
      props: {
        formState: props.formState ?? emptyFormState,
        isConfigured: props.isConfigured ?? false,
        isSaving: props.isSaving ?? false,
        isDeleting: props.isDeleting ?? false,
        isTesting: props.isTesting ?? false,
        hasUnsavedChanges: props.hasUnsavedChanges ?? false,
        provider: props.provider,
        testResult: props.testResult ?? null,
        testError: props.testError,
        error: props.error,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Sender identity fields
  // ─────────────────────────────────────────────────────────────────────────

  describe('Sender identity fields', () => {
    it('renders all sender identity fields', () => {
      wrapper = mountComponent();

      const fromNameInput = wrapper.find('#email-from-name');
      const fromAddressInput = wrapper.find('#email-from-address');
      const replyToInput = wrapper.find('#email-reply-to');

      expect(fromNameInput.exists()).toBe(true);
      expect(fromAddressInput.exists()).toBe(true);
      expect(replyToInput.exists()).toBe(true);
    });

    it('populates sender fields from formState', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const fromNameInput = wrapper.find('#email-from-name');
      const fromAddressInput = wrapper.find('#email-from-address');
      const replyToInput = wrapper.find('#email-reply-to');

      expect((fromNameInput.element as HTMLInputElement).value).toBe('Acme Corp');
      expect((fromAddressInput.element as HTMLInputElement).value).toBe('noreply@acme.com');
      expect((replyToInput.element as HTMLInputElement).value).toBe('support@acme.com');
    });

    it('emits update:formState when from_name input changes', async () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const fromNameInput = wrapper.find('#email-from-name');
      await fromNameInput.trigger('input');
      await flushPromises();

      expect(wrapper.emitted('update:formState')).toBeTruthy();
    });

    it('emits update:formState when from_address input changes', async () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const fromAddressInput = wrapper.find('#email-from-address');
      await fromAddressInput.trigger('input');
      await flushPromises();

      expect(wrapper.emitted('update:formState')).toBeTruthy();
    });

    it('emits update:formState when reply_to input changes', async () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const replyToInput = wrapper.find('#email-reply-to');
      await replyToInput.trigger('input');
      await flushPromises();

      expect(wrapper.emitted('update:formState')).toBeTruthy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Form events
  // ─────────────────────────────────────────────────────────────────────────

  describe('Form events', () => {
    it('emits save event on form submission when form is valid', async () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeTruthy();
    });

    it('does not emit save when form is invalid (missing required fields)', async () => {
      wrapper = mountComponent({
        formState: emptyFormState,
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeFalsy();
    });

    it('emits discard event when discard button is clicked', async () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: true,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find((b) => b.text().includes('Discard Changes'));
      expect(discardButton).toBeDefined();

      await discardButton!.trigger('click');

      expect(wrapper.emitted('discard')).toBeTruthy();
    });

    it('emits delete event after confirmation', async () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        isConfigured: true,
      });

      // Click remove button to show confirmation
      const buttons = wrapper.findAll('button[type="button"]');
      const removeButton = buttons.find((b) => b.text().includes('Remove'));
      expect(removeButton).toBeDefined();
      await removeButton!.trigger('click');
      await flushPromises();

      // Click confirm delete button
      const confirmButtons = wrapper.findAll('button[type="button"]');
      const confirmButton = confirmButtons.find((b) => b.text().includes('Yes, delete'));
      expect(confirmButton).toBeDefined();
      await confirmButton!.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('delete')).toBeTruthy();
    });

    it('emits update:formState when enabled toggle is clicked', async () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const toggle = wrapper.find('[role="switch"]');
      await toggle.trigger('click');
      await flushPromises();

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      // The toggle should flip the enabled value
      expect(emitted![0][0]).toMatchObject({ enabled: false });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Form validation
  // ─────────────────────────────────────────────────────────────────────────

  describe('Form validation', () => {
    it('form is invalid when from_name is empty', async () => {
      wrapper = mountComponent({
        formState: {
          from_name: '',
          from_address: 'valid@example.com',
          reply_to: '',
          enabled: true,
        },
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeFalsy();
    });

    it('form is invalid when from_address is empty', async () => {
      wrapper = mountComponent({
        formState: {
          from_name: 'Acme Corp',
          from_address: '',
          reply_to: '',
          enabled: true,
        },
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeFalsy();
    });

    it('form is invalid when from_address is not a valid email', async () => {
      wrapper = mountComponent({
        formState: {
          from_name: 'Acme Corp',
          from_address: 'not-an-email',
          reply_to: '',
          enabled: true,
        },
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeFalsy();
    });

    it('form is invalid when reply_to is provided but not a valid email', async () => {
      wrapper = mountComponent({
        formState: {
          from_name: 'Acme Corp',
          from_address: 'valid@example.com',
          reply_to: 'invalid-reply',
          enabled: true,
        },
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeFalsy();
    });

    it('form is valid when reply_to is empty (optional field)', async () => {
      wrapper = mountComponent({
        formState: {
          from_name: 'Acme Corp',
          from_address: 'valid@example.com',
          reply_to: '',
          enabled: true,
        },
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeTruthy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Button states
  // ─────────────────────────────────────────────────────────────────────────

  describe('Button states', () => {
    it('save button is disabled when no unsaved changes', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: false,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeDefined();
    });

    it('save button is disabled when isSaving is true', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: true,
        isSaving: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeDefined();
    });

    it('save button shows saving text when isSaving is true', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: true,
        isSaving: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.text()).toContain('Saving...');
    });

    it('save button shows default text when not saving', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.text()).toContain('Save Changes');
    });

    it('discard button is hidden when no unsaved changes', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: false,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find((b) => b.text().includes('Discard Changes'));
      expect(discardButton).toBeUndefined();
    });

    it('discard button is visible when there are unsaved changes', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        hasUnsavedChanges: true,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find((b) => b.text().includes('Discard Changes'));
      expect(discardButton).toBeDefined();
    });

    it('remove button is hidden when not configured', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        isConfigured: false,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const removeButton = buttons.find((b) => b.text().includes('Remove'));
      expect(removeButton).toBeUndefined();
    });

    it('remove button is visible when configured', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        isConfigured: true,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const removeButton = buttons.find((b) => b.text().includes('Remove'));
      expect(removeButton).toBeDefined();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Delete confirmation
  // ─────────────────────────────────────────────────────────────────────────

  describe('Delete confirmation', () => {
    it('shows confirmation text after clicking remove', async () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        isConfigured: true,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const removeButton = buttons.find((b) => b.text().includes('Remove'));
      await removeButton!.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('Are you sure you want to remove this configuration?');
    });

    it('shows cancel button in confirmation state', async () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        isConfigured: true,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const removeButton = buttons.find((b) => b.text().includes('Remove'));
      await removeButton!.trigger('click');
      await flushPromises();

      const cancelButton = wrapper.findAll('button[type="button"]').find((b) => b.text().includes('Cancel'));
      expect(cancelButton).toBeDefined();
    });

    it('hides confirmation after clicking cancel', async () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        isConfigured: true,
      });

      // Show confirmation
      const buttons = wrapper.findAll('button[type="button"]');
      const removeButton = buttons.find((b) => b.text().includes('Remove'));
      await removeButton!.trigger('click');
      await flushPromises();

      // Click cancel
      const cancelButton = wrapper.findAll('button[type="button"]').find((b) => b.text().includes('Cancel'));
      await cancelButton!.trigger('click');
      await flushPromises();

      expect(wrapper.text()).not.toContain('Are you sure you want to remove this configuration?');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Enabled toggle
  // ─────────────────────────────────────────────────────────────────────────

  describe('Enabled toggle', () => {
    it('renders the enabled toggle switch', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.exists()).toBe(true);
    });

    it('reflects the enabled state via aria-checked', () => {
      wrapper = mountComponent({
        formState: { ...configuredFormState, enabled: true },
      });

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.attributes('aria-checked')).toBe('true');
    });

    it('reflects the disabled state via aria-checked', () => {
      wrapper = mountComponent({
        formState: { ...configuredFormState, enabled: false },
      });

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.attributes('aria-checked')).toBe('false');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Fields always editable (enabled toggle does not disable inputs)
  // ─────────────────────────────────────────────────────────────────────────

  describe('Fields always editable', () => {
    it('does not show a disabled notice banner when enabled is false', () => {
      wrapper = mountComponent({
        formState: { ...emptyFormState, enabled: false },
      });

      // The disabled-state banner (.bg-blue-50) was removed; fields are always editable
      const banner = wrapper.find('.bg-blue-50');
      expect(banner.exists()).toBe(false);
    });

    it('form inputs are never disabled regardless of enabled toggle', () => {
      wrapper = mountComponent({
        formState: { ...emptyFormState, enabled: false },
      });

      const fromNameInput = wrapper.find('#email-from-name');
      const fromAddressInput = wrapper.find('#email-from-address');
      const replyToInput = wrapper.find('#email-reply-to');

      expect(fromNameInput.attributes('disabled')).toBeUndefined();
      expect(fromAddressInput.attributes('disabled')).toBeUndefined();
      expect(replyToInput.attributes('disabled')).toBeUndefined();
    });

    it('does not apply opacity styling to form container', () => {
      wrapper = mountComponent({
        formState: { ...emptyFormState, enabled: false },
      });

      const formFieldsContainer = wrapper.find('.opacity-60');
      expect(formFieldsContainer.exists()).toBe(false);
    });

    it('toggle remains interactive when enabled is false', async () => {
      wrapper = mountComponent({
        formState: { ...emptyFormState, enabled: false },
      });

      const toggle = wrapper.find('[role="switch"]');
      await toggle.trigger('click');
      await flushPromises();

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      // Should flip enabled to true
      expect(emitted![0][0]).toMatchObject({ enabled: true });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Error display
  // ─────────────────────────────────────────────────────────────────────────

  describe('Error display', () => {
    it('shows error alert when error prop is provided', () => {
      wrapper = mountComponent({
        formState: configuredFormState,
        error: 'Something went wrong',
      });

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
      expect(alerts.attributes('data-error')).toBe('Something went wrong');
    });

    it('hides error alert when no error prop', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Accessibility
  // ─────────────────────────────────────────────────────────────────────────

  describe('Accessibility', () => {
    it('sender input fields have associated labels', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      expect(wrapper.find('label[for="email-from-name"]').exists()).toBe(true);
      expect(wrapper.find('label[for="email-from-address"]').exists()).toBe(true);
      expect(wrapper.find('label[for="email-reply-to"]').exists()).toBe(true);
    });

    it('required fields are marked with asterisk', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const fromNameLabel = wrapper.find('label[for="email-from-name"]');
      const fromAddressLabel = wrapper.find('label[for="email-from-address"]');

      expect(fromNameLabel.text()).toContain('*');
      expect(fromAddressLabel.text()).toContain('*');
    });

    it('reply_to label does not have asterisk (optional field)', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const replyToLabel = wrapper.find('label[for="email-reply-to"]');
      expect(replyToLabel.text()).not.toContain('*');
    });

    it('enabled toggle has aria-describedby', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const toggle = wrapper.find('[role="switch"]');
      expect(toggle.attributes('aria-describedby')).toBe('email-enabled-hint');
    });

    it('has live region for status announcements', () => {
      wrapper = mountComponent({ formState: configuredFormState });

      const liveRegion = wrapper.find('[aria-live="polite"]');
      expect(liveRegion.exists()).toBe(true);
    });
  });
});
