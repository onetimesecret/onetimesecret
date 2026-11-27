// src/tests/apps/workspace/components/domains/DomainIncomingConfigForm.spec.ts
//
// Tests for the rewritten DomainIncomingConfigForm component. Single
// editable recipients list (no pending vs configured split), no replace
// warning, no serverState prop. The composable owns plaintext recipients;
// the form renders them and emits user intent back.

import { mount, type VueWrapper, flushPromises, DOMWrapper } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { createI18n } from 'vue-i18n';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
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

const i18n = createTestI18n();

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

      expect(wrapper.text()).toContain('web.domains.incoming.empty_state');
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
      expect(wrapper.text()).toContain('web.domains.incoming.validation_max_recipients');
    });
  });

  describe('adding a recipient', () => {
    it('emits addRecipient with email + name', async () => {
      const wrapper = mountForm({ formState: emptyFormState });

      await wrapper.find('input#recipient-email').setValue('new@example.com');
      await wrapper.find('input#recipient-name').setValue('New One');
      await findButtonByText(wrapper, 'web.domains.incoming.add_recipient').trigger('click');

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
      await findButtonByText(wrapper, 'web.domains.incoming.add_recipient').trigger('click');
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

      expect(wrapper.text()).toContain('web.domains.incoming.validation_invalid_email');
      expect(wrapper.emitted('addRecipient')).toBeUndefined();
    });

    it('shows duplicate error when the email already exists in formState', async () => {
      const wrapper = mountForm({ formState: singleRecipientFormState });

      // Email format is valid here, so the Add button is enabled and click
      // reaches handleAddRecipient, which surfaces the duplicate error.
      await wrapper.find('input#recipient-email').setValue('SECURITY@acme.com');
      await findButtonByText(wrapper, 'web.domains.incoming.add_recipient').trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('web.domains.incoming.validation_duplicate_email');
      expect(wrapper.emitted('addRecipient')).toBeUndefined();
    });
  });

  describe('removing a recipient', () => {
    it('emits removeRecipient(index) when the per-row Remove is clicked', async () => {
      const wrapper = mountForm({ formState: multipleRecipientsFormState });

      const removeButtons = wrapper
        .findAll('button')
        .filter((b) => b.attributes('aria-label') === 'web.domains.incoming.remove_recipient');
      expect(removeButtons).toHaveLength(3);

      await removeButtons[1].trigger('click');

      expect(wrapper.emitted('removeRecipient')).toEqual([[1]]);
    });
  });

  describe('save', () => {
    it('save button is hidden when there are no unsaved changes', () => {
      // Recipients/enabled auto-save at the page level, so the Save button
      // only appears as a retry affordance when changes remain unsaved.
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
        hasUnsavedChanges: false,
      });

      const saveButton = wrapper.find('button[type="submit"]');
      expect(saveButton.exists()).toBe(false);
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
      expect(noChanges.text()).not.toContain('web.domains.incoming.discard_changes');

      const withChanges = mountForm({
        formState: singleRecipientFormState,
        savedFormState: emptyFormState,
        hasUnsavedChanges: true,
      });
      expect(withChanges.text()).toContain('web.domains.incoming.discard_changes');
    });

    it('emits discard when the Discard button is clicked', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: emptyFormState,
        hasUnsavedChanges: true,
      });

      const discardButton = wrapper
        .findAll('button')
        .find((b) => b.text().includes('web.domains.incoming.discard_changes'));
      expect(discardButton).toBeDefined();
      await discardButton!.trigger('click');

      expect(wrapper.emitted('discard')).toBeTruthy();
    });
  });

  describe('enabled toggle', () => {
    it('edits the local passphrase requirement and lifetime ceiling', async () => {
      const wrapper = mountForm({ formState: emptyFormState });
      await wrapper.get('input[type="checkbox"]').setValue(true);
      const lifetime = wrapper.get('input[type="number"]');
      await lifetime.setValue('60');
      await lifetime.setValue('');
      expect(wrapper.emitted('update:passphraseRequired')).toEqual([[true]]);
      expect(wrapper.emitted('update:maxTtl')).toEqual([[60], [null]]);
    });

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
      expect(wrapper.text()).not.toContain('web.domains.incoming.delete_all_recipients');
    });

    it('shows the Delete button when savedFormState has recipients', () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
      });
      expect(wrapper.text()).toContain('web.domains.incoming.delete_all_recipients');
    });

    it('shows the Delete button when savedFormState.enabled is true (even with no recipients)', () => {
      // The user toggled enabled and saved, but cleared all recipients without
      // a subsequent save. The persisted record still exists.
      const wrapper = mountForm({
        formState: emptyFormState,
        savedFormState: { ...emptyFormState, enabled: true },
      });
      expect(wrapper.text()).toContain('web.domains.incoming.delete_all_recipients');
    });

    it('reveals the confirmation prompt when Delete is clicked', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
      });
      const deleteBtn = wrapper.findAll('button').find((b) => b.text().includes('web.domains.incoming.delete_all_recipients'));
      await deleteBtn!.trigger('click');

      expect(wrapper.text()).toContain('web.domains.incoming.remove_all_confirmation');
    });

    it('emits delete when confirmation is accepted', async () => {
      const wrapper = mountForm({
        formState: singleRecipientFormState,
        savedFormState: singleRecipientFormState,
      });
      const deleteBtn = wrapper.findAll('button').find((b) => b.text().includes('web.domains.incoming.delete_all_recipients'));
      await deleteBtn!.trigger('click');
      const confirmBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes('web.COMMON.yes_delete'));
      await confirmBtn!.trigger('click');

      expect(wrapper.emitted('delete')).toBeTruthy();
    });
  });

  describe('no more replace-warning dialog (#3095 regression)', () => {
    it('saving with existing recipients does not call window.confirm', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
      const wrapper = mountForm({
        formState: {
          ...multipleRecipientsFormState,
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

describe('DomainIncomingConfigForm field labelling', () => {
  it('labels the passphrase and lifetime controls and ties the lifetime hint to its input', () => {
    const wrapper = mountForm({ formState: emptyFormState });

    const checkbox = wrapper.get('input[type="checkbox"]');
    expect(wrapper.get(`label[for="${checkbox.attributes('id')}"]`).text()).toBe(
      'web.domains.passphrase_required_label',
    );

    const lifetime = wrapper.get('input[type="number"]');
    expect(wrapper.get(`label[for="${lifetime.attributes('id')}"]`).text()).toBe(
      'web.domains.incoming.max_ttl',
    );
    expect(lifetime.attributes('min')).toBe('60');
    expect(wrapper.get(`#${lifetime.attributes('aria-describedby')}`).text()).toBe(
      'web.domains.incoming.max_ttl_hint',
    );
  });
});

describe('DomainIncomingConfigForm when a higher level already requires a passphrase', () => {
  const checkbox = '#incoming-passphrase-required';
  const note = '[data-testid="incoming-passphrase-inherited"]';

  function mountInherited(levels: {
    instance?: boolean;
    organization?: boolean;
    domain?: boolean;
    orgid?: string;
  }) {
    const pinia = createTestingPinia({ createSpy: vi.fn });
    useBootstrapStore().$patch({
      secret_options: {
        default_ttl: 3600,
        ttl_options: [3600],
        passphrase: { required: !!levels.instance, minimum_length: 4, maximum_length: 128 },
      },
    });
    useOrganizationStore().$patch({
      organizations: [
        {
          extid: 'on-owner',
          sharing_policy: {
            recipient_email_mode: 'unrestricted',
            recipient_email_domains: [],
            passphrase_required: !!levels.organization,
            max_ttl: null,
          },
        },
      ] as never,
    });
    return mount(DomainIncomingConfigForm, {
      props: {
        formState: emptyFormState,
        savedFormState: null,
        ...(levels.orgid === undefined ? {} : { orgid: levels.orgid }),
        ...(levels.domain === undefined ? {} : { domainPassphraseRequired: levels.domain }),
      },
      global: { plugins: [pinia, i18n] },
    });
  }

  it('shows the box checked and disabled with the installation note', () => {
    const wrapper = mountInherited({ instance: true, orgid: 'on-owner' });
    const box = wrapper.get<HTMLInputElement>(checkbox);

    expect(emptyFormState.passphrase_required).toBe(false);
    expect(box.element.checked).toBe(true);
    expect(box.element.disabled).toBe(true);
    // The test i18n renders keys.
    expect(wrapper.get(note).text()).toBe('web.domains.incoming.passphrase_required_by_instance');
    expect(box.attributes('aria-describedby')).toBe(wrapper.get(note).attributes('id'));
    expect(wrapper.emitted('update:passphraseRequired')).toBeUndefined();
  });

  it('shows the box checked and disabled with the organization note', () => {
    const wrapper = mountInherited({ organization: true, orgid: 'on-owner' });
    const box = wrapper.get<HTMLInputElement>(checkbox);

    expect(box.element.checked).toBe(true);
    expect(box.element.disabled).toBe(true);
    expect(wrapper.get(note).text()).toBe(
      'web.domains.incoming.passphrase_required_by_organization'
    );
  });

  it('names the installation when both levels require one', () => {
    const wrapper = mountInherited({ instance: true, organization: true, orgid: 'on-owner' });
    expect(wrapper.get(note).text()).toBe('web.domains.incoming.passphrase_required_by_instance');
  });

  it("shows the box checked and disabled with the domain note when the domain's brand requires one", () => {
    const wrapper = mountInherited({ domain: true, orgid: 'on-owner' });
    const box = wrapper.get<HTMLInputElement>(checkbox);

    expect(box.element.checked).toBe(true);
    expect(box.element.disabled).toBe(true);
    expect(wrapper.get(note).text()).toBe('web.domains.incoming.passphrase_required_by_domain');
  });

  it('names the organization when both the organization and the domain require one', () => {
    const wrapper = mountInherited({ organization: true, domain: true, orgid: 'on-owner' });
    expect(wrapper.get(note).text()).toBe(
      'web.domains.incoming.passphrase_required_by_organization'
    );
  });

  it('applies the domain level even when no organization is given', () => {
    const wrapper = mountInherited({ domain: true });
    expect(wrapper.get<HTMLInputElement>(checkbox).element.disabled).toBe(true);
  });

  it('leaves the box editable when neither level requires one', () => {
    const wrapper = mountInherited({ orgid: 'on-owner' });
    const box = wrapper.get<HTMLInputElement>(checkbox);

    expect(box.element.checked).toBe(false);
    expect(box.element.disabled).toBe(false);
    expect(wrapper.find(note).exists()).toBe(false);
  });

  it('ignores the organization level for an organization the store has not loaded', () => {
    const wrapper = mountInherited({ organization: true, orgid: 'on-other' });
    expect(wrapper.get<HTMLInputElement>(checkbox).element.disabled).toBe(false);
  });

  it('ignores the organization level when no organization is given', () => {
    const wrapper = mountInherited({ organization: true });
    expect(wrapper.get<HTMLInputElement>(checkbox).element.disabled).toBe(false);
  });
});

describe('DomainIncomingConfigForm recipients section copy', () => {
  it('describes the section with the section description, not the empty-state text', () => {
    const wrapper = mountForm({ formState: singleRecipientFormState });

    // The test i18n renders keys.
    expect(wrapper.get('[data-testid="incoming-recipients-description"]').text()).toBe(
      'web.domains.incoming.recipients_description'
    );
    expect(wrapper.text()).not.toContain('web.domains.incoming.empty_state_description');
  });

  it('heads the list with a heading key, not the status badge key', () => {
    const wrapper = mountForm({ formState: singleRecipientFormState });

    expect(wrapper.get('[data-testid="incoming-recipients-list-heading"]').text()).toContain(
      'web.domains.incoming.recipients_list_heading'
    );
    expect(wrapper.text()).not.toContain('web.domains.incoming.badge_configured');
  });

  it('renders the usage line from one key with count and max, without lower-casing a translation', () => {
    // Pass-through like the test i18n, with real text for the one key under test.
    const usageI18n = createI18n({
      legacy: false,
      locale: 'en',
      missingWarn: false,
      fallbackWarn: false,
      missing: (_, key) => key,
      // `never`: the generated message schema expects every key (see createTestI18n).
      messages: {
        en: { web: { domains: { incoming: { recipients_usage: '{count} OF {max} Recipients' } } } },
      } as never,
    });
    const wrapper = mount(DomainIncomingConfigForm, {
      props: { formState: singleRecipientFormState, savedFormState: null, maxRecipients: 20 },
      global: { plugins: [createTestingPinia({ createSpy: vi.fn }), usageI18n] },
    });

    // Capitals survive: the text is the translator's, not passed through toLowerCase().
    expect(wrapper.get('[data-testid="incoming-recipients-usage"]').text()).toBe(
      '1 OF 20 Recipients'
    );
  });

  it('shows no usage line without recipients', () => {
    const wrapper = mountForm({ formState: emptyFormState });
    expect(wrapper.find('[data-testid="incoming-recipients-usage"]').exists()).toBe(false);
  });
});
