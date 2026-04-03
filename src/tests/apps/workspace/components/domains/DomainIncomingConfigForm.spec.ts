// src/tests/apps/workspace/components/domains/DomainIncomingConfigForm.spec.ts
//
// Tests for DomainIncomingConfigForm.vue covering:
// 1. Recipients list rendering (server state and form state)
// 2. Recipient input fields and validation
// 3. Event emissions (save, discard, delete, add/remove recipient)
// 4. Button states
// 5. Delete confirmation flow
// 6. Accessibility attributes
//
// Dual-state design: serverState (hashed, read-only) + formState (plaintext, editable)

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import DomainIncomingConfigForm from '@/apps/workspace/components/domains/DomainIncomingConfigForm.vue';
import {
  emptyFormState,
  emptyServerState,
  singleRecipientFormState,
  singleRecipientServerState,
  multipleRecipientsFormState,
  multipleRecipientsServerState,
  maxRecipientsFormState,
} from '../../../../fixtures/incomingConfig.fixture';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// i18n setup
// ---------------------------------------------------------------------------

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          verified: 'Verified',
          pending_verification: 'Pending Verification',
          incoming: {
            recipients_title: 'Recipients',
            recipients_description: 'Recipients will receive incoming secrets sent to this domain.',
            badge_configured: 'Configured',
            add_recipient: 'Add Recipient',
            email_label: 'Email Address',
            email_placeholder: "security{'@'}example.com",
            name_label: 'Display Name (optional)',
            name_placeholder: 'Security Team',
            remove_recipient: 'Remove',
            delete_all_recipients: 'Delete All Recipients',
            remove_all_confirmation: 'Are you sure you want to remove all recipients? External users will no longer be able to send secrets to this domain.',
            save_will_replace_confirmation: 'Saving will replace all existing recipients with your pending changes. Are you sure?',
            save_changes: 'Save Changes',
            discard_changes: 'Discard Changes',
            empty_state: 'No recipients configured',
            empty_state_description: 'Add email addresses to receive incoming secrets.',
            validation_email_required: 'Email address is required',
            validation_invalid_email: 'Enter a valid email address',
            validation_duplicate_email: 'This email is already added',
            validation_max_recipients: 'Maximum {max} recipients allowed',
            remove_all_confirmation: 'Are you sure you want to remove all recipients? External users will no longer be able to send secrets to this domain.',
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DomainIncomingConfigForm', () => {
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
    formState: typeof emptyFormState;
    serverState: typeof emptyServerState;
    isLoading: boolean;
    isSaving: boolean;
    isDeleting: boolean;
    hasUnsavedChanges: boolean;
    maxRecipients: number;
    error: string;
  }> = {}) => {
    return mount(DomainIncomingConfigForm, {
      props: {
        formState: props.formState ?? emptyFormState,
        serverState: props.serverState ?? emptyServerState,
        isLoading: props.isLoading ?? false,
        isSaving: props.isSaving ?? false,
        isDeleting: props.isDeleting ?? false,
        hasUnsavedChanges: props.hasUnsavedChanges ?? false,
        maxRecipients: props.maxRecipients ?? 20,
        error: props.error,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  // ---------------------------------------------------------------------------
  // Recipients List Rendering
  // ---------------------------------------------------------------------------

  describe('Recipients list rendering', () => {
    it('FC-RENDER-001: renders all server recipients (existing/configured)', () => {
      wrapper = mountComponent({
        serverState: multipleRecipientsServerState,
      });

      const recipientItems = wrapper.findAll('li');
      expect(recipientItems.length).toBe(3);
    });

    it('FC-RENDER-002: shows empty state when no recipients', () => {
      wrapper = mountComponent({
        formState: emptyFormState,
        serverState: emptyServerState,
      });

      expect(wrapper.text()).toContain('No recipients configured');
    });

    it('renders pending recipients from formState with amber styling', () => {
      wrapper = mountComponent({
        formState: multipleRecipientsFormState,
        serverState: emptyServerState,
      });

      const pendingSection = wrapper.find('.border-amber-300');
      expect(pendingSection.exists()).toBe(true);

      const pendingItems = pendingSection.findAll('li');
      expect(pendingItems.length).toBe(3);
    });

    it('FC-RENDER-003: shows recipient count badge', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        serverState: multipleRecipientsServerState,
      });

      // Total: 3 server + 1 pending = 4
      expect(wrapper.text()).toContain('4 / 20');
    });

    it('displays display_name for server recipients', () => {
      wrapper = mountComponent({
        serverState: singleRecipientServerState,
      });

      expect(wrapper.text()).toContain('Security Team');
    });

    it('displays email for pending recipients', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
      });

      expect(wrapper.text()).toContain('security@acme.com');
    });
  });

  // ---------------------------------------------------------------------------
  // Recipient Input Fields
  // ---------------------------------------------------------------------------

  describe('Recipient input fields', () => {
    it('FC-INPUT-001: email input accepts valid email', async () => {
      wrapper = mountComponent();

      const emailInput = wrapper.find('#recipient-email');
      await emailInput.setValue('valid@example.com');
      await flushPromises();

      // No error should be shown
      expect(wrapper.find('#email-error').exists()).toBe(false);
    });

    it('FC-INPUT-002: add button disabled for invalid email format', async () => {
      wrapper = mountComponent();

      const emailInput = wrapper.find('#recipient-email');
      // Use a clearly invalid email that Zod will reject
      await emailInput.setValue('not@');
      await flushPromises();

      // Find add button
      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );

      // The add button should be disabled when email is invalid
      expect(addButton!.attributes('disabled')).toBeDefined();
    });

    it('FC-INPUT-003: name input is optional', async () => {
      wrapper = mountComponent();

      // Set only email, no name
      const emailInput = wrapper.find('#recipient-email');
      await emailInput.setValue('test@example.com');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      // Should emit addRecipient with undefined name
      const emitted = wrapper.emitted('addRecipient');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['test@example.com', undefined]);
    });

    it('FC-INPUT-004: add button disabled when email empty', async () => {
      wrapper = mountComponent();

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );

      expect(addButton!.attributes('disabled')).toBeDefined();
    });

    it('FC-INPUT-005: add form hidden when at max recipients (form + server)', () => {
      wrapper = mountComponent({
        formState: maxRecipientsFormState,
        serverState: emptyServerState,
      });

      // Add form should not be rendered
      const emailInput = wrapper.find('#recipient-email');
      expect(emailInput.exists()).toBe(false);

      // Should show limit message
      expect(wrapper.text()).toContain('Maximum 20 recipients allowed');
    });
  });

  // ---------------------------------------------------------------------------
  // Event Emissions
  // ---------------------------------------------------------------------------

  describe('Event emissions', () => {
    it('FC-EMIT-001: emits addRecipient on add button click', async () => {
      wrapper = mountComponent();

      const emailInput = wrapper.find('#recipient-email');
      const nameInput = wrapper.find('#recipient-name');

      await emailInput.setValue('new@example.com');
      await nameInput.setValue('New User');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      const emitted = wrapper.emitted('addRecipient');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['new@example.com', 'New User']);
    });

    it('FC-EMIT-002: emits removeRecipient on remove click', async () => {
      wrapper = mountComponent({
        formState: multipleRecipientsFormState,
      });

      // Find remove buttons in pending section
      const removeButtons = wrapper.findAll('button').filter(
        (b) => b.attributes('aria-label') === 'Remove'
      );

      await removeButtons[0].trigger('click');
      await flushPromises();

      const emitted = wrapper.emitted('removeRecipient');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([0]);
    });

    it('FC-EMIT-003: emits save on form submission', async () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        hasUnsavedChanges: true,
      });

      const form = wrapper.find('form');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('save')).toBeTruthy();
    });

    it('FC-EMIT-004: emits discard on discard button click', async () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        hasUnsavedChanges: true,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find((b) => b.text().includes('Discard Changes'));
      await discardButton!.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('discard')).toBeTruthy();
    });

    it('FC-EMIT-005: emits delete after confirmation', async () => {
      wrapper = mountComponent({
        serverState: singleRecipientServerState,
      });

      // Click delete all button to show confirmation
      const buttons = wrapper.findAll('button[type="button"]');
      const deleteAllButton = buttons.find((b) => b.text().includes('Delete All Recipients'));
      await deleteAllButton!.trigger('click');
      await flushPromises();

      // Click confirm delete button
      const confirmButtons = wrapper.findAll('button[type="button"]');
      const confirmButton = confirmButtons.find((b) => b.text().includes('Yes, delete'));
      await confirmButton!.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('delete')).toBeTruthy();
    });

    it('clears input fields after successful add', async () => {
      wrapper = mountComponent();

      const emailInput = wrapper.find('#recipient-email') as VueWrapper<HTMLInputElement>;
      const nameInput = wrapper.find('#recipient-name') as VueWrapper<HTMLInputElement>;

      await emailInput.setValue('new@example.com');
      await nameInput.setValue('New User');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      // Inputs should be cleared
      expect((emailInput.element as HTMLInputElement).value).toBe('');
      expect((nameInput.element as HTMLInputElement).value).toBe('');
    });
  });

  // ---------------------------------------------------------------------------
  // Form Validation
  // ---------------------------------------------------------------------------

  describe('Form validation', () => {
    it('FC-VALID-001: shows error for duplicate email in form state', async () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
      });

      const emailInput = wrapper.find('#recipient-email');
      await emailInput.setValue('security@acme.com');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('This email is already added');
    });

    it('shows error when email is empty on add', async () => {
      wrapper = mountComponent();

      // Type and then clear
      const emailInput = wrapper.find('#recipient-email');
      await emailInput.setValue('');
      await emailInput.trigger('keydown', { key: 'Enter' });
      await flushPromises();

      // Button should still be disabled, no addRecipient emitted
      expect(wrapper.emitted('addRecipient')).toBeFalsy();
    });

    it('clears error on email input', async () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
      });

      const emailInput = wrapper.find('#recipient-email');
      // Use a duplicate email to trigger an error
      await emailInput.setValue('security@acme.com');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      expect(wrapper.find('#email-error').exists()).toBe(true);

      // Start typing again
      await emailInput.trigger('input');
      await flushPromises();

      expect(wrapper.find('#email-error').exists()).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Button States
  // ---------------------------------------------------------------------------

  describe('Button states', () => {
    it('FC-BTN-001: save button disabled when no pending recipients', () => {
      wrapper = mountComponent({
        formState: emptyFormState,
        serverState: singleRecipientServerState,
        hasUnsavedChanges: false,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeDefined();
    });

    it('FC-BTN-002: save button disabled when isSaving', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        hasUnsavedChanges: true,
        isSaving: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeDefined();
    });

    it('FC-BTN-003: save button shows "Saving..." when isSaving', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        hasUnsavedChanges: true,
        isSaving: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.text()).toContain('Saving...');
    });

    it('FC-BTN-004: discard button hidden when no unsaved changes', () => {
      wrapper = mountComponent({
        formState: emptyFormState,
        hasUnsavedChanges: false,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const discardButton = buttons.find((b) => b.text().includes('Discard Changes'));
      expect(discardButton).toBeUndefined();
    });

    it('FC-BTN-005: delete all button hidden when no server recipients', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        serverState: emptyServerState,
      });

      // The "delete all" button should not be present when there are no server recipients
      // Note: Individual "Remove" buttons for pending recipients will still exist
      const actionBar = wrapper.find('.border-t');
      const deleteAllButton = actionBar.findAll('button[type="button"]').find(
        (b) => b.text().includes('Delete All Recipients')
      );
      expect(deleteAllButton).toBeUndefined();
    });

    it('save button enabled when there are pending recipients', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
        hasUnsavedChanges: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeUndefined();
    });
  });

  // ---------------------------------------------------------------------------
  // Delete Confirmation
  // ---------------------------------------------------------------------------

  describe('Delete confirmation', () => {
    it('FC-DEL-001: shows confirmation text after clicking delete all', async () => {
      wrapper = mountComponent({
        serverState: singleRecipientServerState,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const deleteAllButton = buttons.find((b) => b.text().includes('Delete All Recipients'));
      await deleteAllButton!.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('Are you sure you want to remove all recipients? External users will no longer be able to send secrets to this domain.');
    });

    it('FC-DEL-002: shows cancel button in confirmation state', async () => {
      wrapper = mountComponent({
        serverState: singleRecipientServerState,
      });

      const buttons = wrapper.findAll('button[type="button"]');
      const deleteAllButton = buttons.find((b) => b.text().includes('Delete All Recipients'));
      await deleteAllButton!.trigger('click');
      await flushPromises();

      const cancelButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Cancel')
      );
      expect(cancelButton).toBeDefined();
    });

    it('FC-DEL-003: hides confirmation after clicking cancel', async () => {
      wrapper = mountComponent({
        serverState: singleRecipientServerState,
      });

      // Show confirmation
      const buttons = wrapper.findAll('button[type="button"]');
      const deleteAllButton = buttons.find((b) => b.text().includes('Delete All Recipients'));
      await deleteAllButton!.trigger('click');
      await flushPromises();

      // Click cancel
      const cancelButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Cancel')
      );
      await cancelButton!.trigger('click');
      await flushPromises();

      expect(wrapper.text()).not.toContain('Are you sure you want to remove all recipients? External users will no longer be able to send secrets to this domain.');
    });

    it('FC-DEL-004: does not emit delete until confirm clicked', async () => {
      wrapper = mountComponent({
        serverState: singleRecipientServerState,
      });

      // First click on Delete All Recipients
      const buttons = wrapper.findAll('button[type="button"]');
      const deleteAllButton = buttons.find((b) => b.text().includes('Delete All Recipients'));
      await deleteAllButton!.trigger('click');
      await flushPromises();

      // Delete should NOT be emitted yet
      expect(wrapper.emitted('delete')).toBeFalsy();
    });
  });

  // ---------------------------------------------------------------------------
  // Accessibility
  // ---------------------------------------------------------------------------

  describe('Accessibility', () => {
    it('FC-A11Y-001: email input has associated label', () => {
      wrapper = mountComponent();

      expect(wrapper.find('label[for="recipient-email"]').exists()).toBe(true);
    });

    it('FC-A11Y-002: name input has associated label', () => {
      wrapper = mountComponent();

      expect(wrapper.find('label[for="recipient-name"]').exists()).toBe(true);
    });

    it('FC-A11Y-003: remove buttons have aria-label', () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
      });

      const removeButton = wrapper.findAll('button').find(
        (b) => b.attributes('aria-label') === 'Remove'
      );
      expect(removeButton).toBeDefined();
    });

    it('FC-A11Y-004: has live region for status announcements', () => {
      wrapper = mountComponent();

      const liveRegion = wrapper.find('[aria-live="polite"]');
      expect(liveRegion.exists()).toBe(true);
    });

    it('email input has required marker', () => {
      wrapper = mountComponent();

      const emailLabel = wrapper.find('label[for="recipient-email"]');
      expect(emailLabel.text()).toContain('*');
    });

    it('email input sets aria-invalid when error present', async () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
      });

      const emailInput = wrapper.find('#recipient-email');
      // Use a duplicate email to trigger an error
      await emailInput.setValue('security@acme.com');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      // Re-find the input element after state update
      const updatedEmailInput = wrapper.find('#recipient-email');
      expect(updatedEmailInput.attributes('aria-invalid')).toBe('true');
    });

    it('email input has aria-describedby when error present', async () => {
      wrapper = mountComponent({
        formState: singleRecipientFormState,
      });

      const emailInput = wrapper.find('#recipient-email');
      // Use a duplicate email to trigger an error
      await emailInput.setValue('security@acme.com');

      const addButton = wrapper.findAll('button[type="button"]').find(
        (b) => b.text().includes('Add Recipient')
      );
      await addButton!.trigger('click');
      await flushPromises();

      // Re-find the input element after state update
      const updatedEmailInput = wrapper.find('#recipient-email');
      expect(updatedEmailInput.attributes('aria-describedby')).toBe('email-error');
    });
  });

  // ---------------------------------------------------------------------------
  // Error display
  // ---------------------------------------------------------------------------

  describe('Error display', () => {
    it('shows error alert when error prop is provided', () => {
      wrapper = mountComponent({
        error: 'Something went wrong',
      });

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
      expect(alerts.attributes('data-error')).toBe('Something went wrong');
    });

    it('hides error alert when no error prop', () => {
      wrapper = mountComponent();

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Enter key handling
  // ---------------------------------------------------------------------------

  describe('Enter key handling', () => {
    it('adds recipient on Enter in email input', async () => {
      wrapper = mountComponent();

      const emailInput = wrapper.find('#recipient-email');
      await emailInput.setValue('test@example.com');
      await emailInput.trigger('keydown', { key: 'Enter' });
      await flushPromises();

      const emitted = wrapper.emitted('addRecipient');
      expect(emitted).toBeTruthy();
    });

    it('adds recipient on Enter in name input', async () => {
      wrapper = mountComponent();

      const emailInput = wrapper.find('#recipient-email');
      const nameInput = wrapper.find('#recipient-name');

      await emailInput.setValue('test@example.com');
      await nameInput.setValue('Test User');
      await nameInput.trigger('keydown', { key: 'Enter' });
      await flushPromises();

      const emitted = wrapper.emitted('addRecipient');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['test@example.com', 'Test User']);
    });
  });
});
