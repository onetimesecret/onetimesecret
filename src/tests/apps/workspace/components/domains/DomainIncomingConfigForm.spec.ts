// src/tests/apps/workspace/components/domains/DomainIncomingConfigForm.spec.ts
//
// Tests for the rewritten DomainIncomingConfigForm component. Single
// editable recipients list (no pending vs configured split), no replace
// warning, no serverState prop. The composable owns plaintext recipients;
// the form renders them and emits user intent back.

import { mount, type VueWrapper, flushPromises, DOMWrapper } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import DomainIncomingConfigForm from '@/apps/workspace/components/domains/DomainIncomingConfigForm.vue';
import {
  emptyFormState,
  singleRecipientFormState,
  multipleRecipientsFormState,
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
// i18n
// ---------------------------------------------------------------------------

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          enabled: 'Enabled',
          incoming: {
            add_recipient: 'Add Recipient',
            badge_configured: 'Configured',
            delete_all_recipients: 'Delete all',
            disabled_notice: 'Disabled',
            discard_changes: 'Discard',
            email_label: 'Email',
            email_placeholder: "name{'@'}example.com",
            empty_state: 'No recipients yet',
            empty_state_description: 'Add up to 20 recipients',
            enabled_hint: 'Toggle incoming secrets',
            name_label: 'Name',
            name_placeholder: 'Display name',
            recipients_title: 'Recipients',
            remove_all_confirmation: 'Remove all?',
            remove_recipient: 'Remove',
            save_changes: 'Save',
            validation_duplicate_email: 'Already added',
            validation_email_required: 'Required',
            validation_invalid_email: 'Invalid email',
            validation_max_recipients: 'Maximum {max} recipients',
          },
        },
        COMMON: {
          processing: 'Working…',
          saving: 'Saving…',
          word_cancel: 'Cancel',
          yes_delete: 'Yes, delete',
        },
      },
    },
  },
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface MountOptions {
  formState?: typeof emptyFormState;
  savedFormState?: typeof emptyFormState | null;
  hasUnsavedChanges?: boolean;
  isSaving?: boolean;
  isDeleting?: boolean;
  maxRecipients?: number;
  error?: string;
}

function mountForm(opts: MountOptions = {}): VueWrapper {
  return mount(DomainIncomingConfigForm, {
    props: {
      formState: opts.formState ?? emptyFormState,
      savedFormState: opts.savedFormState ?? null,
      hasUnsavedChanges: opts.hasUnsavedChanges ?? false,
      isSaving: opts.isSaving ?? false,
      isDeleting: opts.isDeleting ?? false,
      maxRecipients: opts.maxRecipients ?? 20,
      error: opts.error,
    },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn }), i18n],
    },
    attachTo: document.body,
  });
}

/** Find a button by its rendered text (case-insensitive substring match). */
function findButtonByText(wrapper: VueWrapper, label: string): DOMWrapper<HTMLButtonElement> {
  const lower = label.toLowerCase();
  const found = wrapper
    .findAll('button')
    .find((b) => b.text().toLowerCase().includes(lower));
  if (!found) {
    throw new Error(`No button with text matching "${label}"; rendered: ${wrapper.text()}`);
  }
  return found as DOMWrapper<HTMLButtonElement>;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DomainIncomingConfigForm (single-list, plaintext)', () => {
  describe('rendering', () => {
    it('renders the empty state when there are no recipients', () => {
      const wrapper = mountForm({ formState: emptyFormState });

      expect(wrapper.text()).toContain('No recipients yet');
      expect(wrapper.findAll('li')).toHaveLength(0);
    });

    it('renders one row per recipient from formState (plaintext email + name)', () => {
      const wrapper = mountForm({ formState: multipleRecipientsFormState });

      const items = wrapper.findAll('li');
      expect(items).toHaveLength(3);
      expect(items[0].text()).toContain('Security Team');
      expect(items[0].text()).toContain('security@acme.com');
      expect(items[1].text()).toContain('Support');
      expect(items[1].text()).toContain('support@acme.com');
    });

    it('hides the add row when at max capacity', () => {
      const wrapper = mountForm({ formState: maxRecipientsFormState, maxRecipients: 20 });

      expect(wrapper.find('input#recipient-email').exists()).toBe(false);
      expect(wrapper.text()).toContain('Maximum 20 recipients');
    });
  });

  describe('adding a recipient', () => {
    it('emits addRecipient with email + name', async () => {
      const wrapper = mountForm({ formState: emptyFormState });

      await wrapper.find('input#recipient-email').setValue('new@example.com');
      await wrapper.find('input#recipient-name').setValue('New One');
      await findButtonByText(wrapper, 'Add Recipient').trigger('click');

      const emitted = wrapper.emitted('addRecipient');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['new@example.com', 'New One']);
    });

    it('clears the input fields after a successful add', async () => {
      const wrapper = mountForm({ formState: emptyFormState });
      const emailInput = wrapper.find<HTMLInputElement>('input#recipient-email');
      const nameInput = wrapper.find<HTMLInputElement>('input#recipient-name');

      await emailInput.setValue('new@example.com');
      await nameInput.setValue('New One');
      await findButtonByText(wrapper, 'Add Recipient').trigger('click');
      await flushPromises();

      expect(emailInput.element.value).toBe('');
      expect(nameInput.element.value).toBe('');
    });

    it('shows an inline error for an invalid email and does not emit', async () => {
      const wrapper = mountForm({ formState: emptyFormState });

      // Press Enter on the email input — bypasses the disabled-button guard
      // that fires when isAddFormValid is false (invalid email format).
      await wrapper.find('input#recipient-email').setValue('not-an-email');
      await wrapper.find('input#recipient-email').trigger('keydown.enter');
      await flushPromises();

      expect(wrapper.text()).toContain('Invalid email');
      expect(wrapper.emitted('addRecipient')).toBeUndefined();
    });

    it('shows duplicate error when the email already exists in formState', async () => {
      const wrapper = mountForm({ formState: singleRecipientFormState });

      // Email format is valid here, so the Add button is enabled and click
      // reaches handleAddRecipient, which surfaces the duplicate error.
      await wrapper.find('input#recipient-email').setValue('SECURITY@acme.com');
      await findButtonByText(wrapper, 'Add Recipient').trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('Already added');
      expect(wrapper.emitted('addRecipient')).toBeUndefined();
    });
  });

  describe('removing a recipient', () => {
    it('emits removeRecipient(index) when the per-row Remove is clicked', async () => {
      const wrapper = mountForm({ formState: multipleRecipientsFormState });

      const removeButtons = wrapper
        .findAll('button')
        .filter((b) => b.attributes('aria-label') === 'Remove');
      expect(removeButtons).toHaveLength(3);

      await removeButtons[1].trigger('click');

      expect(wrapper.emitted('removeRecipient')).toEqual([[1]]);
    });
  });

  describe('save', () => {
    it('save button is disabled when there are no unsaved changes', () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
        hasUnsavedChanges: false,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeDefined();
    });

    it('save button is enabled when there are unsaved changes', () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: emptyFormState,
        hasUnsavedChanges: true,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.attributes('disabled')).toBeUndefined();
    });

    it('emits save on submit when changes are pending', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: emptyFormState,
        hasUnsavedChanges: true,
      });

      await wrapper.find('form').trigger('submit.prevent');

      expect(wrapper.emitted('save')).toBeTruthy();
    });

    it('does not emit save when hasUnsavedChanges is false', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
        hasUnsavedChanges: false,
      });

      await wrapper.find('form').trigger('submit.prevent');

      expect(wrapper.emitted('save')).toBeUndefined();
    });
  });

  describe('discard', () => {
    it('shows the Discard button only when there are unsaved changes', () => {
      const noChanges = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
        hasUnsavedChanges: false,
      });
      expect(noChanges.text()).not.toContain('Discard');

      const withChanges = mountForm({
        formState: singleRecipientFormState,
        savedFormState: emptyFormState,
        hasUnsavedChanges: true,
      });
      expect(withChanges.text()).toContain('Discard');
    });

    it('emits discard when the Discard button is clicked', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: emptyFormState,
        hasUnsavedChanges: true,
      });

      const discardButton = wrapper
        .findAll('button')
        .find((b) => b.text().includes('Discard'));
      expect(discardButton).toBeDefined();
      await discardButton!.trigger('click');

      expect(wrapper.emitted('discard')).toBeTruthy();
    });
  });

  describe('enabled toggle', () => {
    it('emits update:enabled with the negated value', async () => {
      const wrapper = mountForm({ formState: emptyFormState });
      const toggle = wrapper.find('button[role="switch"]');

      await toggle.trigger('click');

      expect(wrapper.emitted('update:enabled')).toEqual([[true]]);
    });

    it('reflects the current enabled state via aria-checked', () => {
      const off = mountForm({ formState: emptyFormState });
      expect(off.find('button[role="switch"]').attributes('aria-checked')).toBe('false');

      const on = mountForm({ formState: singleRecipientFormState });
      expect(on.find('button[role="switch"]').attributes('aria-checked')).toBe('true');
    });
  });

  describe('delete', () => {
    it('hides the Delete button when there is no persisted state', () => {
      const wrapper = mountForm({
        formState: emptyFormState,
        savedFormState: emptyFormState,
      });
      expect(wrapper.text()).not.toContain('Delete all');
    });

    it('shows the Delete button when savedFormState has recipients', () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
      });
      expect(wrapper.text()).toContain('Delete all');
    });

    it('shows the Delete button when savedFormState.enabled is true (even with no recipients)', () => {
      // The user toggled enabled and saved, but cleared all recipients without
      // a subsequent save. The persisted record still exists.
      const wrapper = mountForm({
        formState: emptyFormState,
        savedFormState: { enabled: true, recipients: [] },
      });
      expect(wrapper.text()).toContain('Delete all');
    });

    it('reveals the confirmation prompt when Delete is clicked', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
      });
      const deleteBtn = wrapper.findAll('button').find((b) => b.text().includes('Delete all'));
      await deleteBtn!.trigger('click');

      expect(wrapper.text()).toContain('Remove all?');
    });

    it('emits delete when confirmation is accepted', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
      });
      const deleteBtn = wrapper.findAll('button').find((b) => b.text().includes('Delete all'));
      await deleteBtn!.trigger('click');
      const confirmBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes('Yes, delete'));
      await confirmBtn!.trigger('click');

      expect(wrapper.emitted('delete')).toBeTruthy();
    });
  });

  describe('no more replace-warning dialog (#3095 regression)', () => {
    it('saving with existing recipients does not call window.confirm', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
      const wrapper = mountForm({
        formState: {
          enabled: true,
          recipients: [
            ...multipleRecipientsFormState.recipients,
            { email: 'newcomer@acme.com', name: 'Newcomer' },
          ],
        },
        savedFormState: multipleRecipientsFormState,
        hasUnsavedChanges: true,
      });

      await wrapper.find('form').trigger('submit.prevent');

      expect(confirmSpy).not.toHaveBeenCalled();
      expect(wrapper.emitted('save')).toBeTruthy();
      confirmSpy.mockRestore();
    });
  });
});
