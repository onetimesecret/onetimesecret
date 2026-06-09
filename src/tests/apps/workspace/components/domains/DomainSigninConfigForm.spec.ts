// src/tests/apps/workspace/components/domains/DomainSigninConfigForm.spec.ts
//
// Tests for DomainSigninConfigForm.vue covering:
// 1. Loading skeleton display
// 2. Form rendering with props
// 3. updateField emits update:formState with merged payload
// 4. restrict_to radio group (including "show all" -> null)
// 5. Enabled toggle (aria-checked, click emits)
// 6. Save/delete/discard emit flow
// 7. Delete confirmation two-step
// 8. Disabled states during saving/deleting
// 9. Button label changes based on isConfigured

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
            signin_enabled_label: 'Sign-in enabled',
            signin_enabled_hint: 'Whether sign-in is available on this domain',
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
            enabled_label: 'Per-domain config active',
            enabled_hint: 'Master switch for this signin configuration',
            delete_config: 'Delete config',
            delete_confirm: 'Are you sure?',
            save_config: 'Create config',
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

const _configuredFormState: SigninConfigFormState = {
  enabled: true,
  signin_enabled: true,
  restrict_to: null,
  email_auth_enabled: true,
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
    },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn }), i18n],
    },
    attachTo: document.body,
  });
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
    it('renders signin_enabled select', () => {
      wrapper = mountForm();
      const select = wrapper.find('#signin-domain-enabled');
      expect(select.exists()).toBe(true);
    });

    it('renders email_auth select', () => {
      wrapper = mountForm();
      const select = wrapper.find('#signin-email-auth');
      expect(select.exists()).toBe(true);
    });

    it('renders sso select', () => {
      wrapper = mountForm();
      const select = wrapper.find('#signin-sso');
      expect(select.exists()).toBe(true);
    });

    it('renders enabled toggle switch', () => {
      wrapper = mountForm();
      const toggle = wrapper.find('#signin-enabled');
      expect(toggle.exists()).toBe(true);
      expect(toggle.attributes('role')).toBe('switch');
    });

    it('renders restrict_to radio group with "show all" option', () => {
      wrapper = mountForm();
      const showAllRadio = wrapper.find('#signin-restrict-none');
      expect(showAllRadio.exists()).toBe(true);
    });

    it('renders all four restrict_to method radios', () => {
      wrapper = mountForm();
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // Enabled toggle
  // -----------------------------------------------------------------------

  describe('enabled toggle', () => {
    it('reflects formState.enabled in aria-checked', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, enabled: true } });
      const toggle = wrapper.find('#signin-enabled');
      expect(toggle.attributes('aria-checked')).toBe('true');
    });

    it('reflects formState.enabled=false in aria-checked', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, enabled: false } });
      const toggle = wrapper.find('#signin-enabled');
      expect(toggle.attributes('aria-checked')).toBe('false');
    });

    it('emits update:formState with toggled enabled on click', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, enabled: false } });
      const toggle = wrapper.find('#signin-enabled');
      await toggle.trigger('click');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![0][0]).toEqual(
        expect.objectContaining({ enabled: true })
      );
    });
  });

  // -----------------------------------------------------------------------
  // Select fields (signin_enabled, email_auth, sso)
  // -----------------------------------------------------------------------

  describe('select field updates', () => {
    it('emits update:formState when signin_enabled changes', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, signin_enabled: true } });
      const select = wrapper.find('#signin-domain-enabled');

      await select.setValue('false');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![0][0]).toEqual(
        expect.objectContaining({ signin_enabled: false })
      );
    });

    it('emits update:formState when email_auth_enabled changes', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, email_auth_enabled: false } });
      const select = wrapper.find('#signin-email-auth');

      await select.setValue('true');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![0][0]).toEqual(
        expect.objectContaining({ email_auth_enabled: true })
      );
    });

    it('emits update:formState when sso_enabled changes', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, sso_enabled: false } });
      const select = wrapper.find('#signin-sso');

      await select.setValue('true');

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toBeTruthy();
      expect(emitted![0][0]).toEqual(
        expect.objectContaining({ sso_enabled: true })
      );
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
      wrapper = mountForm();
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

    it('disables submit button when isSaving', () => {
      wrapper = mountForm({ isSaving: true });
      const submit = wrapper.find('button[type="submit"]');
      expect(submit.attributes('disabled')).toBeDefined();
    });

    it('disables submit button when isDeleting', () => {
      wrapper = mountForm({ isDeleting: true });
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
    it('signin_enabled select has aria-describedby', () => {
      wrapper = mountForm();
      const select = wrapper.find('#signin-domain-enabled');
      expect(select.attributes('aria-describedby')).toBe('signin-domain-enabled-hint');
    });

    it('email_auth select has aria-describedby', () => {
      wrapper = mountForm();
      const select = wrapper.find('#signin-email-auth');
      expect(select.attributes('aria-describedby')).toBe('signin-email-auth-hint');
    });

    it('sso select has aria-describedby', () => {
      wrapper = mountForm();
      const select = wrapper.find('#signin-sso');
      expect(select.attributes('aria-describedby')).toBe('signin-sso-hint');
    });

    it('enabled toggle has role="switch"', () => {
      wrapper = mountForm();
      const toggle = wrapper.find('#signin-enabled');
      expect(toggle.attributes('role')).toBe('switch');
    });

    it('enabled toggle has aria-describedby', () => {
      wrapper = mountForm();
      const toggle = wrapper.find('#signin-enabled');
      expect(toggle.attributes('aria-describedby')).toBe('signin-enabled-hint');
    });

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
  });
});
