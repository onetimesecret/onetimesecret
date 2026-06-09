// src/tests/apps/workspace/components/domains/DomainSigninConfigForm.spec.ts
//
// Tests for DomainSigninConfigForm.vue covering:
// 1. Loading skeleton display
// 2. Form rendering with props (restrict_to radios + method-override toggles)
// 3. updateField emits update:formState with merged payload (radios)
// 4. restrict_to radio group (including "show all" -> null)
// 5. Method-override toggles auto-save (emit 'auto-save' with field + value)
// 6. Per-toggle loading feedback via savingField
// 7. Save/delete/discard emit flow
// 8. Save button disabled on load (no unsaved changes) and while saving/deleting
// 9. Delete confirmation two-step
// 10. Button label changes based on isConfigured

import { mount, type VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import DomainSigninConfigForm from '@/apps/workspace/components/domains/DomainSigninConfigForm.vue';
import type { SigninConfigFormState } from '@/shared/composables/useSigninConfig';

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

vi.mock('@/shared/components/closet/SettingsSkeleton.vue', () => ({
  default: {
    name: 'SettingsSkeleton',
    template: '<div data-testid="settings-skeleton" />',
    props: ['heading'],
  },
}));

// Stub the toggle so we can assert role/state/emit without headlessui internals.
vi.mock('@/shared/components/common/ToggleWithIcon.vue', () => ({
  default: {
    name: 'ToggleWithIcon',
    props: ['enabled', 'disabled', 'loading', 'onLabel', 'offLabel'],
    emits: ['update:enabled'],
    template: `
      <button
        type="button"
        role="switch"
        :aria-checked="String(enabled)"
        :data-loading="String(loading)"
        :disabled="disabled || loading"
        @click="$emit('update:enabled', !enabled)" />
    `,
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
          signin: {
            restrict_to_label: 'Restrict to single method',
            restrict_to_hint: 'Limit the login page to one authentication method',
            all_methods: 'Show all methods',
            all_methods_description: 'Display all enabled authentication methods',
            method_password: 'Password',
            method_email_auth: 'Email Auth',
            method_webauthn: 'WebAuthn',
            method_sso: 'SSO',
            method_overrides_label: 'Authentication method overrides',
            method_overrides_hint: 'Enable or disable specific methods for this domain',
            email_auth_label: 'Email Authentication',
            email_auth_hint: 'Passwordless magic link sign-in',
            sso_enabled_label: 'Single Sign-On',
            sso_enabled_hint: 'External identity provider',
            delete_config: 'Delete config',
            delete_confirm: 'Are you sure?',
            save_config: 'Create config',
          },
          sso: {
            configure_button: 'Configure',
            edit_credentials: 'Edit credentials',
            upgrade_required: 'Upgrade required',
          },
          email: {
            discard_changes: 'Discard changes',
          },
        },
        COMMON: {
          enabled: 'Enabled',
          disabled: 'Disabled',
          saving: 'Saving...',
          processing: 'Processing...',
          save_changes: 'Save changes',
          yes_delete: 'Yes, delete',
          word_cancel: 'Cancel',
        },
      },
    },
  },
});

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const defaultFormState: SigninConfigFormState = {
  enabled: false,
  signin_enabled: true,
  restrict_to: null,
  email_auth_enabled: false,
  sso_enabled: false,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface MountOptions {
  formState?: SigninConfigFormState;
  isLoading?: boolean;
  isSaving?: boolean;
  isDeleting?: boolean;
  hasUnsavedChanges?: boolean;
  isConfigured?: boolean;
  ssoConfigured?: boolean;
  canManageSso?: boolean;
  savingField?: keyof SigninConfigFormState | null;
}

function mountForm(opts: MountOptions = {}): VueWrapper {
  return mount(DomainSigninConfigForm, {
    props: {
      domainExtId: 'dm-ext-test',
      formState: opts.formState ?? defaultFormState,
      isLoading: opts.isLoading ?? false,
      isSaving: opts.isSaving ?? false,
      isDeleting: opts.isDeleting ?? false,
      hasUnsavedChanges: opts.hasUnsavedChanges ?? false,
      isConfigured: opts.isConfigured ?? false,
      ssoConfigured: opts.ssoConfigured ?? false,
      canManageSso: opts.canManageSso ?? true,
      savingField: opts.savingField ?? null,
    },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn }), i18n],
    },
    attachTo: document.body,
  });
}

/** Method-override toggles in render order: [0] email_auth, [1] sso. */
function toggles(wrapper: VueWrapper) {
  return wrapper.findAll('[role="switch"]');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DomainSigninConfigForm', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  // -----------------------------------------------------------------------
  // Loading state
  // -----------------------------------------------------------------------

  describe('loading state', () => {
    it('shows skeleton when isLoading is true', () => {
      wrapper = mountForm({ isLoading: true });
      expect(wrapper.find('[data-testid="settings-skeleton"]').exists()).toBe(true);
    });

    it('hides form when isLoading is true', () => {
      wrapper = mountForm({ isLoading: true });
      expect(wrapper.find('form').exists()).toBe(false);
    });

    it('shows form when isLoading is false', () => {
      wrapper = mountForm({ isLoading: false });
      expect(wrapper.find('form').exists()).toBe(true);
    });

    it('hides skeleton when isLoading is false', () => {
      wrapper = mountForm({ isLoading: false });
      expect(wrapper.find('[data-testid="settings-skeleton"]').exists()).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // Form rendering
  // -----------------------------------------------------------------------

  describe('form rendering', () => {
    it('renders restrict_to radio group with "show all" option', () => {
      wrapper = mountForm();
      expect(wrapper.find('#signin-restrict-none').exists()).toBe(true);
    });

    it('renders all four restrict_to method radios', () => {
      wrapper = mountForm();
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
    });

    it('renders the two method-override toggles (email_auth, sso)', () => {
      wrapper = mountForm();
      expect(toggles(wrapper)).toHaveLength(2);
    });

    it('renders the SSO Configure button when canManageSso', () => {
      wrapper = mountForm({ canManageSso: true });
      const configureBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Configure')
      );
      expect(configureBtn).toBeTruthy();
    });

    it('renders the upgrade hint instead of Configure when not canManageSso', () => {
      wrapper = mountForm({ canManageSso: false });
      expect(wrapper.text()).toContain('Upgrade required');
      const configureBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Configure')
      );
      expect(configureBtn).toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Method-override toggles (auto-save)
  // -----------------------------------------------------------------------

  describe('method-override toggles', () => {
    it('email_auth toggle reflects formState in aria-checked', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, email_auth_enabled: true } });
      expect(toggles(wrapper)[0].attributes('aria-checked')).toBe('true');
    });

    it('sso toggle reflects formState in aria-checked', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, sso_enabled: true } });
      expect(toggles(wrapper)[1].attributes('aria-checked')).toBe('true');
    });

    it('email_auth toggle emits auto-save with field and value', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, email_auth_enabled: false } });
      await toggles(wrapper)[0].trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['email_auth_enabled', true]);
    });

    it('sso toggle emits auto-save with field and value', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, sso_enabled: false } });
      await toggles(wrapper)[1].trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['sso_enabled', true]);
    });

    it('does not emit update:formState from the toggles (auto-save only)', async () => {
      wrapper = mountForm();
      await toggles(wrapper)[0].trigger('click');
      expect(wrapper.emitted('update:formState')).toBeFalsy();
    });

    it('disables both toggles while isSaving', () => {
      wrapper = mountForm({ isSaving: true });
      expect(toggles(wrapper)[0].attributes('disabled')).toBeDefined();
      expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
    });

    it('shows loading only on the field being auto-saved', () => {
      wrapper = mountForm({ isSaving: true, savingField: 'email_auth_enabled' });
      expect(toggles(wrapper)[0].attributes('data-loading')).toBe('true');
      expect(toggles(wrapper)[1].attributes('data-loading')).toBe('false');
    });
  });

  // -----------------------------------------------------------------------
  // Restrict-to radio group
  // -----------------------------------------------------------------------

  describe('restrict_to radio group', () => {
    it('"show all" radio is checked when restrict_to is null', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      const radio = wrapper.find('#signin-restrict-none');
      expect((radio.element as HTMLInputElement).checked).toBe(true);
    });

    it('method radio is checked when restrict_to matches', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const radio = wrapper.find('#signin-restrict-sso');
      expect((radio.element as HTMLInputElement).checked).toBe(true);
    });

    it('"show all" radio is unchecked when a method is selected', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      const radio = wrapper.find('#signin-restrict-none');
      expect((radio.element as HTMLInputElement).checked).toBe(false);
    });

    it('clicking "show all" emits restrict_to: null', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const radio = wrapper.find('#signin-restrict-none');
      await radio.trigger('change');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![0][0]).toEqual(
        expect.objectContaining({ restrict_to: null })
      );
    });

    it('clicking a method radio emits that method value', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      const radio = wrapper.find('#signin-restrict-webauthn');
      await radio.trigger('change');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![0][0]).toEqual(
        expect.objectContaining({ restrict_to: 'webauthn' })
      );
    });
  });

  // -----------------------------------------------------------------------
  // Save / submit
  // -----------------------------------------------------------------------

  describe('save', () => {
    it('emits save on form submit', async () => {
      wrapper = mountForm({ hasUnsavedChanges: true });
      await wrapper.find('form').trigger('submit');

      expect(wrapper.emitted('save')).toBeTruthy();
    });

    it('shows "Save changes" when isConfigured', () => {
      wrapper = mountForm({ isConfigured: true });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.text()).toContain('Save changes');
    });

    it('shows "Create config" when not isConfigured', () => {
      wrapper = mountForm({ isConfigured: false });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.text()).toContain('Create config');
    });

    it('shows saving spinner text when isSaving', () => {
      wrapper = mountForm({ isSaving: true });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.text()).toContain('Saving...');
    });

    it('disables submit button on load (no unsaved changes)', () => {
      wrapper = mountForm({ hasUnsavedChanges: false });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.attributes('disabled')).toBeDefined();
    });

    it('enables submit button when there are unsaved changes', () => {
      wrapper = mountForm({ hasUnsavedChanges: true });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.attributes('disabled')).toBeUndefined();
    });

    it('disables submit button when isSaving', () => {
      wrapper = mountForm({ hasUnsavedChanges: true, isSaving: true });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.attributes('disabled')).toBeDefined();
    });

    it('disables submit button when isDeleting', () => {
      wrapper = mountForm({ hasUnsavedChanges: true, isDeleting: true });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.attributes('disabled')).toBeDefined();
    });
  });

  // -----------------------------------------------------------------------
  // Delete confirmation flow
  // -----------------------------------------------------------------------

  describe('delete flow', () => {
    it('shows delete button when isConfigured', () => {
      wrapper = mountForm({ isConfigured: true });
      const deleteBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Delete config')
      );
      expect(deleteBtn).toBeTruthy();
    });

    it('does not show delete button when not isConfigured', () => {
      wrapper = mountForm({ isConfigured: false });
      const deleteBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Delete config')
      );
      expect(deleteBtn).toBeUndefined();
    });

    it('shows confirmation prompt after clicking delete', async () => {
      wrapper = mountForm({ isConfigured: true });
      const deleteBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Delete config')
      )!;
      await deleteBtn.trigger('click');

      expect(wrapper.text()).toContain('Are you sure?');
    });

    it('emits delete when confirmation is accepted', async () => {
      wrapper = mountForm({ isConfigured: true });

      // Click delete to show confirmation
      const deleteBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Delete config')
      )!;
      await deleteBtn.trigger('click');

      // Click confirm
      const confirmBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Yes, delete')
      )!;
      await confirmBtn.trigger('click');

      expect(wrapper.emitted('delete')).toBeTruthy();
    });

    it('hides confirmation prompt when cancel is clicked', async () => {
      wrapper = mountForm({ isConfigured: true });

      // Show confirmation
      const deleteBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Delete config')
      )!;
      await deleteBtn.trigger('click');

      expect(wrapper.text()).toContain('Are you sure?');

      // Cancel
      const cancelBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Cancel')
      )!;
      await cancelBtn.trigger('click');

      expect(wrapper.text()).not.toContain('Are you sure?');
    });
  });

  // -----------------------------------------------------------------------
  // Discard changes
  // -----------------------------------------------------------------------

  describe('discard changes', () => {
    it('shows discard button when hasUnsavedChanges is true', () => {
      wrapper = mountForm({ hasUnsavedChanges: true });
      const discardBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Discard changes')
      );
      expect(discardBtn).toBeTruthy();
    });

    it('hides discard button when hasUnsavedChanges is false', () => {
      wrapper = mountForm({ hasUnsavedChanges: false });
      const discardBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Discard changes')
      );
      expect(discardBtn).toBeUndefined();
    });

    it('emits discard when discard button is clicked', async () => {
      wrapper = mountForm({ hasUnsavedChanges: true });
      const discardBtn = wrapper.findAll('button').find(
        (b) => b.text().includes('Discard changes')
      )!;
      await discardBtn.trigger('click');

      expect(wrapper.emitted('discard')).toBeTruthy();
    });
  });

  // -----------------------------------------------------------------------
  // Accessibility
  // -----------------------------------------------------------------------

  describe('accessibility', () => {
    it('restrict_to container has role="radiogroup"', () => {
      wrapper = mountForm();
      const group = wrapper.find('[role="radiogroup"]');
      expect(group.exists()).toBe(true);
    });

    it('restrict_to method radios have aria-describedby linking to description', () => {
      wrapper = mountForm();
      const radio = wrapper.find('#signin-restrict-password');
      expect(radio.attributes('aria-describedby')).toBe('signin-restrict-password-description');
    });

    it('method-override toggles expose role="switch"', () => {
      wrapper = mountForm();
      expect(toggles(wrapper)).toHaveLength(2);
      toggles(wrapper).forEach((t) => {
        expect(t.attributes('role')).toBe('switch');
      });
    });
  });
});
