// src/tests/apps/workspace/components/domains/DomainSigninConfigForm.spec.ts
//
// Tests for DomainSigninConfigForm.vue covering the three-mode design:
// 1. Loading skeleton display
// 2. Mode switch (Any available method / One specific method / Sign-in
//    disabled) as radiogroup
// 3. Mode A: static rows + availability toggles (email_auth, sso), auto-save
// 4. Mode B: single-choice restrict_to radios, picking flips availability flag
// 5. Disabled mode (#3415): persists signin_enabled=false, hides method UI,
//    preserves restrict_to/flags; re-enabling transitions save atomically
// 6. Global availability gating hides unavailable methods in both method modes
// 7. SSO Configure reachable in both method modes; upgrade hint when
//    !canManageSso, and the SSO toggle (Mode A) / radio (Mode B) render locked
// 8. Per-field loading feedback via savingField
// 9. Delete confirmation two-step
// 10. Accessibility (radiogroup roles, aria-describedby, role="switch")

import { readFileSync } from 'fs';
import { resolve } from 'path';
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
// i18n — load the REAL generated bundle, not invented strings.
//
// The previous version built createI18n with inline messages, so it supplied
// the very strings it asserted ("How can users sign in?") — blind by
// construction. Loading generated/locales/en.json instead means assertions
// verify the component's i18n WIRING: each key resolves to the copy that
// actually ships. A key the component references but that is missing/stale in
// the bundle renders as the raw path, breaking the text assertions below.
//
// Division of labor: detecting keys referenced in code but never authored
// anywhere is handled generically by src/tests/i18n/key-validation.spec.ts.
// That coupling matters — `toContain(COPY.x)` is tautological for a TRULY
// missing key (both the render and COPY collapse to the same key path), so
// key-validation is the net for that class; this spec verifies copy wiring.
// ---------------------------------------------------------------------------

const realEn = JSON.parse(
  readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')
);

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: realEn },
});

/** Resolve a key against the real bundle. */
const t = (key: string) => i18n.global.t(key);

/**
 * Copy the component renders, sourced from the bundle — never hand-typed here.
 * Assertions reference these so they track the shipped copy automatically.
 */
const COPY = {
  configure: t('web.domains.sso.configure_button'),
  editCredentials: t('web.domains.sso.edit_credentials'),
  upgradeRequired: t('web.domains.sso.upgrade_required'),
  availabilityGlobalOn: t('web.domains.signin.availability_global_on'),
  availabilityGlobalOff: t('web.domains.signin.availability_global_off'),
  availabilityUnavailable: t('web.domains.signin.availability_unavailable'),
  allowOnDomain: t('web.domains.signin.allow_on_domain'),
  modeDisabledHint: t('web.domains.signin.mode_disabled_hint'),
  modeDisabledNotice: t('web.domains.signin.mode_disabled_notice'),
  resetToDefaults: t('web.domains.signin.reset_to_defaults'),
  resetConfirm: t('web.domains.signin.reset_confirm'),
  resetAction: t('web.domains.signin.reset_action'),
  cancel: t('web.COMMON.word_cancel'),
} as const;

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

const allAvailable = { email_auth: true, webauthn: true, sso: true };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface MountOptions {
  formState?: SigninConfigFormState;
  isLoading?: boolean;
  isSaving?: boolean;
  isDeleting?: boolean;
  isConfigured?: boolean;
  workspaceDefault?: boolean;
  ssoConfigured?: boolean;
  canManageSso?: boolean;
  globalAvailability?: { email_auth: boolean; webauthn: boolean; sso: boolean };
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
      isConfigured: opts.isConfigured ?? false,
      // Most of this suite exercises an explicitly-configured domain, where
      // the no-change early-returns apply; the ADR-024 materialization block
      // below flips this on.
      workspaceDefault: opts.workspaceDefault ?? false,
      ssoConfigured: opts.ssoConfigured ?? false,
      canManageSso: opts.canManageSso ?? true,
      globalAvailability: opts.globalAvailability ?? allAvailable,
      savingField: opts.savingField ?? null,
    },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn }), i18n],
    },
    attachTo: document.body,
  });
}

/** Availability toggles in Mode A render order: [0] email_auth, [1] sso. */
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

    it('hides the mode switch when isLoading is true', () => {
      wrapper = mountForm({ isLoading: true });
      expect(wrapper.find('#signin-mode-any').exists()).toBe(false);
    });

    it('shows the mode switch when isLoading is false', () => {
      wrapper = mountForm({ isLoading: false });
      expect(wrapper.find('#signin-mode-any').exists()).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // Mode switch
  // -----------------------------------------------------------------------

  describe('mode switch', () => {
    it('defaults to "Any available method" when restrict_to is null', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('false');
    });

    it('is in "One specific method" mode when restrict_to is set', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('false');
    });

    it('clicking "Any available method" with a restriction set auto-saves restrict_to: null', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      await wrapper.find('#signin-mode-any').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      // Assert the full tuple: patch AND the 'restrict_to' field-key, matching
      // the Mode A toggle tests. The field-key drives per-field saving feedback,
      // so an unasserted second arg would let a regression slip through.
      expect(emitted![0]).toEqual([{ restrict_to: null }, 'restrict_to']);
    });

    it('clicking "Any available method" when already null does not auto-save', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-any').trigger('click');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('clicking "One specific method" reveals the picker without auto-saving', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');

      // Picker is revealed (radio list rendered) but nothing persisted yet.
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });
  });

  // -----------------------------------------------------------------------
  // Mode: Sign-in disabled (#3415)
  //
  // Third segment in the mode switch. signin_enabled === false wins over a
  // preserved restrict_to for display; transitions persist signin_enabled
  // atomically with whatever else the target mode requires.
  // -----------------------------------------------------------------------

  describe('mode: sign-in disabled', () => {
    const disabledFormState: SigninConfigFormState = {
      ...defaultFormState,
      signin_enabled: false,
    };

    it('renders the third segment in the mode switch', () => {
      wrapper = mountForm();
      expect(wrapper.find('#signin-mode-disabled').exists()).toBe(true);
      expect(wrapper.find('#signin-mode-disabled').attributes('role')).toBe('radio');
    });

    it('is checked when signin_enabled is false', () => {
      wrapper = mountForm({ formState: disabledFormState });
      expect(wrapper.find('#signin-mode-disabled').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('false');
      expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('false');
    });

    it('wins over a preserved restrict_to for display', () => {
      wrapper = mountForm({ formState: { ...disabledFormState, restrict_to: 'sso' } });
      expect(wrapper.find('#signin-mode-disabled').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('false');
    });

    it('clicking "Sign-in disabled" auto-saves signin_enabled=false', async () => {
      wrapper = mountForm(); // defaultFormState has signin_enabled: true
      await wrapper.find('#signin-mode-disabled').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ signin_enabled: false }, 'signin_enabled']);
    });

    it('clicking it again when already disabled does not auto-save', async () => {
      wrapper = mountForm({ formState: disabledFormState });
      await wrapper.find('#signin-mode-disabled').trigger('click');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('disabling does NOT clear restrict_to or availability flags (preserved for re-enable)', async () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso', sso_enabled: true },
      });
      await wrapper.find('#signin-mode-disabled').trigger('click');

      const patch = wrapper.emitted('auto-save')![0][0] as Partial<SigninConfigFormState>;
      expect(Object.keys(patch)).toEqual(['signin_enabled']);
    });

    it('hides method toggles and radios while disabled', () => {
      wrapper = mountForm({ formState: { ...disabledFormState, restrict_to: 'sso' } });
      expect(toggles(wrapper)).toHaveLength(0);
      expect(wrapper.findAll('input[type="radio"][name="restrict_to"]')).toHaveLength(0);
    });

    it('shows the disabled-mode hint and notice', () => {
      wrapper = mountForm({ formState: disabledFormState });
      expect(wrapper.find('#signin-mode-hint').text()).toContain(COPY.modeDisabledHint);
      expect(wrapper.find('[data-testid="signin-disabled-mode-notice"]').text()).toContain(
        COPY.modeDisabledNotice
      );
    });

    it('does not show the notice in the method modes', () => {
      wrapper = mountForm();
      expect(wrapper.find('[data-testid="signin-disabled-mode-notice"]').exists()).toBe(false);
    });

    it('re-enabling via "Any available method" saves signin_enabled=true with matching field key', async () => {
      // The saving-field hint must name what is actually in the patch: a
      // pure re-enable (restrict_to already null) saves signin_enabled only.
      wrapper = mountForm({ formState: disabledFormState });
      await wrapper.find('#signin-mode-any').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ signin_enabled: true }, 'signin_enabled']);
    });

    it('re-enabling via Any also clears a preserved restrict_to atomically', async () => {
      wrapper = mountForm({ formState: { ...disabledFormState, restrict_to: 'sso' } });
      await wrapper.find('#signin-mode-any').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted![0]).toEqual([
        { restrict_to: null, signin_enabled: true },
        'restrict_to',
      ]);
    });

    it('re-enabling via "One specific method" saves signin_enabled=true immediately', async () => {
      // Unlike the Any→One transition (which persists nothing until a method
      // is picked), leaving the disabled state must persist signin_enabled
      // right away — the public page should stop showing the notice.
      wrapper = mountForm({ formState: disabledFormState });
      await wrapper.find('#signin-mode-one').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ signin_enabled: true }, 'signin_enabled']);
    });

    it('mode switch segments are disabled while saving', () => {
      wrapper = mountForm({ isSaving: true });
      expect(wrapper.find('#signin-mode-disabled').attributes('disabled')).toBeDefined();
    });
  });

  // -----------------------------------------------------------------------
  // Mode A — availability toggles
  // -----------------------------------------------------------------------

  describe('mode A: availability toggles', () => {
    it('renders the two availability toggles (email_auth, sso)', () => {
      wrapper = mountForm();
      expect(toggles(wrapper)).toHaveLength(2);
    });

    it('email_auth toggle reflects formState in aria-checked', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, email_auth_enabled: true } });
      expect(toggles(wrapper)[0].attributes('aria-checked')).toBe('true');
    });

    it('sso toggle reflects formState in aria-checked', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, sso_enabled: true } });
      expect(toggles(wrapper)[1].attributes('aria-checked')).toBe('true');
    });

    it('email_auth toggle auto-saves a partial patch', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, email_auth_enabled: false } });
      await toggles(wrapper)[0].trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ email_auth_enabled: true }, 'email_auth_enabled']);
    });

    it('sso toggle auto-saves a partial patch', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, sso_enabled: false } });
      await toggles(wrapper)[1].trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ sso_enabled: true }, 'sso_enabled']);
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

    it('disables the email toggle when email_auth is globally unavailable', () => {
      wrapper = mountForm({ globalAvailability: { ...allAvailable, email_auth: false } });
      expect(toggles(wrapper)[0].attributes('disabled')).toBeDefined();
    });
  });

  // -----------------------------------------------------------------------
  // Mode A — SSO Configure
  // -----------------------------------------------------------------------

  describe('mode A: SSO configure', () => {
    it('renders the SSO Configure button when canManageSso', () => {
      wrapper = mountForm({ canManageSso: true });
      const configureBtn = wrapper.findAll('button').find((b) => b.text().includes(COPY.configure));
      expect(configureBtn).toBeTruthy();
    });

    it('emits configure-sso when Configure is clicked', async () => {
      wrapper = mountForm({ canManageSso: true });
      const configureBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.configure))!;
      await configureBtn.trigger('click');
      expect(wrapper.emitted('configure-sso')).toBeTruthy();
    });

    it('renders the upgrade hint instead of Configure when not canManageSso', () => {
      wrapper = mountForm({ canManageSso: false });
      expect(wrapper.text()).toContain(COPY.upgradeRequired);
      const configureBtn = wrapper.findAll('button').find((b) => b.text().includes(COPY.configure));
      expect(configureBtn).toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Entitlement gating — SSO controls lock when !canManageSso
  //
  // Without the manage-SSO entitlement the org cannot configure SSO
  // credentials, so SSO can never activate on the domain. An operable
  // "Enabled" toggle next to the "Upgrade to configure" lock contradicted
  // that (and persisted a flag that could never take effect).
  // -----------------------------------------------------------------------

  describe('entitlement gating: canManageSso=false locks SSO controls', () => {
    it('disables the sso availability toggle in Mode A', () => {
      wrapper = mountForm({ canManageSso: false });
      expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
    });

    it('forces the sso toggle visually off even if formState says enabled', () => {
      wrapper = mountForm({
        canManageSso: false,
        formState: { ...defaultFormState, sso_enabled: true },
      });
      expect(toggles(wrapper)[1].attributes('aria-checked')).toBe('false');
    });

    it('leaves the email toggle operable', () => {
      wrapper = mountForm({ canManageSso: false });
      expect(toggles(wrapper)[0].attributes('disabled')).toBeUndefined();
    });

    it('keeps the SSO radio visible in Mode B (upgrade prompt) but disabled', () => {
      wrapper = mountForm({
        canManageSso: false,
        formState: { ...defaultFormState, restrict_to: 'password' },
      });
      const radio = wrapper.find('#signin-restrict-sso');
      expect(radio.exists()).toBe(true);
      expect(radio.attributes('disabled')).toBeDefined();
    });

    it('never saves restrict_to: sso when unentitled', async () => {
      // Belt & suspenders: the disabled attribute blocks the event AND
      // selectMethod guards the value — removing either alone stays safe;
      // this test fails only if both regress (the original bug).
      wrapper = mountForm({
        canManageSso: false,
        formState: { ...defaultFormState, restrict_to: 'password' },
      });
      await wrapper.find('#signin-restrict-sso').trigger('change');
      expect(wrapper.emitted('auto-save')).toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Mode B — restrict_to radio list
  // -----------------------------------------------------------------------

  describe('mode B: restrict_to picker', () => {
    it('renders a radio for each globally-available method', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
    });

    it('pre-selects the active method radio', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const radio = wrapper.find('#signin-restrict-sso');
      expect((radio.element as HTMLInputElement).checked).toBe(true);
    });

    it('picking Email auto-saves restrict_to AND flips email_auth_enabled in one patch', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      await wrapper.find('#signin-restrict-email_auth').trigger('change');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([
        { restrict_to: 'email_auth', email_auth_enabled: true },
        'restrict_to',
      ]);
    });

    it('picking SSO auto-saves restrict_to AND flips sso_enabled in one patch', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      await wrapper.find('#signin-restrict-sso').trigger('change');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ restrict_to: 'sso', sso_enabled: true }, 'restrict_to']);
    });

    it('picking Password auto-saves restrict_to only (no per-domain flag)', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      await wrapper.find('#signin-restrict-password').trigger('change');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted![0]).toEqual([{ restrict_to: 'password' }, 'restrict_to']);
    });

    it('does not render availability toggles in Mode B', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      expect(toggles(wrapper)).toHaveLength(0);
    });

    it('keeps SSO Configure reachable in Mode B', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const configureBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.configure) || b.text().includes(COPY.editCredentials));
      expect(configureBtn).toBeTruthy();
      await configureBtn!.trigger('click');
      expect(wrapper.emitted('configure-sso')).toBeTruthy();
    });
  });

  // -----------------------------------------------------------------------
  // Invariant 1 — Availability-flag flip on Mode B selection (webauthn gap)
  //
  // The existing "mode B: restrict_to picker" block covers Email (+flag),
  // SSO (+flag), and Password (no flag). The Passkeys/webauthn branch — the
  // 4th method, restrict_to only, no per-domain field — was uncovered.
  // -----------------------------------------------------------------------

  describe('invariant 1: Mode B selection flips availability flag', () => {
    it('picking Passkeys auto-saves restrict_to: webauthn only (no per-domain flag)', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      await wrapper.find('#signin-restrict-webauthn').trigger('change');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ restrict_to: 'webauthn' }, 'restrict_to']);
    });

    it('Email/SSO picks carry ONLY their own flag, not the sibling flag', async () => {
      // Picking Email must not also set sso_enabled, and vice versa: the patch
      // is exactly { restrict_to, <own flag> } — no leakage onto other methods.
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      await wrapper.find('#signin-restrict-email_auth').trigger('change');

      const patch = wrapper.emitted('auto-save')![0][0] as Partial<SigninConfigFormState>;
      expect(patch).not.toHaveProperty('sso_enabled');
      expect(Object.keys(patch).sort()).toEqual(['email_auth_enabled', 'restrict_to']);
    });
  });

  // -----------------------------------------------------------------------
  // Invariant 2 — Global availability gating (both branches, all 3 methods)
  //
  // Existing tests cover only the Mode B *omit* branch for sso/webauthn and
  // a single Mode A email-toggle-disabled case. This block fills:
  //   - Mode B omit for email_auth (the missing 3rd method)
  //   - the *available* branch for each method in Mode B (radio present)
  //   - Mode A unavailable state for webauthn (static "global off" reason),
  //     email_auth and sso (toggle disabled + "Unavailable" reason text).
  //
  // Note on `undefined ⇒ available`: the component receives a concrete
  // `boolean` (required prop). The `!== false` normalization lives upstream
  // in DomainSignin.vue (globalAvailability computed), so undefined never
  // reaches this component. We therefore test only the true/false branches
  // here; the undefined⇒available contract is verified at the parent, not
  // testable in isolation against this presentational component.
  // -----------------------------------------------------------------------

  describe('invariant 2: global availability gating', () => {
    describe('Mode B (one specific method) — radio presence', () => {
      it('offers all four radios when everything is globally available', () => {
        wrapper = mountForm({
          formState: { ...defaultFormState, restrict_to: 'password' },
          globalAvailability: allAvailable,
        });
        expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
        expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(true);
        expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(true);
        expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
      });

      it('omits the Email radio when email_auth is globally off', () => {
        wrapper = mountForm({
          formState: { ...defaultFormState, restrict_to: 'password' },
          globalAvailability: { ...allAvailable, email_auth: false },
        });
        expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(false);
      });

      it('an unavailable method is not selectable (radio absent, cannot fire change)', () => {
        // The contradiction guard: a method off site-wide must never become a
        // restrict_to value, which would render a blank login page.
        wrapper = mountForm({
          formState: { ...defaultFormState, restrict_to: 'password' },
          globalAvailability: { email_auth: false, webauthn: false, sso: false },
        });
        expect(wrapper.findAll('input[type="radio"][name="restrict_to"]')).toHaveLength(1);
      });
    });

    describe('Mode A (any available method) — unavailable state', () => {
      it('shows the WebAuthn static "global off" reason when webauthn is off', () => {
        wrapper = mountForm({ globalAvailability: { ...allAvailable, webauthn: false } });
        expect(wrapper.text()).toContain(COPY.availabilityGlobalOff);
      });

      it('shows the WebAuthn static "global on" reason when webauthn is on', () => {
        wrapper = mountForm({ globalAvailability: allAvailable });
        expect(wrapper.text()).toContain(COPY.availabilityGlobalOn);
      });

      it('disables the email toggle and shows "Unavailable" reason when email_auth is off', () => {
        wrapper = mountForm({ globalAvailability: { ...allAvailable, email_auth: false } });
        expect(toggles(wrapper)[0].attributes('disabled')).toBeDefined();
        expect(wrapper.find('#signin-email-auth-hint').text()).toContain(COPY.availabilityUnavailable);
      });

      it('shows "Allow on this domain" reason for email when available', () => {
        wrapper = mountForm({ globalAvailability: allAvailable });
        expect(wrapper.find('#signin-email-auth-hint').text()).toContain(COPY.allowOnDomain);
      });

      it('disables the sso toggle and shows "Unavailable" reason when sso is off', () => {
        wrapper = mountForm({ globalAvailability: { ...allAvailable, sso: false } });
        expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
        expect(wrapper.find('#signin-sso-hint').text()).toContain(COPY.availabilityUnavailable);
      });

      it('shows "Allow on this domain" reason for sso when available', () => {
        wrapper = mountForm({ globalAvailability: allAvailable });
        expect(wrapper.find('#signin-sso-hint').text()).toContain(COPY.allowOnDomain);
      });

      it('forces the email toggle visually off when globally unavailable, even if formState says enabled', () => {
        // AND semantics: a stale email_auth_enabled=true must not show "on" once
        // the global flag drops to false.
        wrapper = mountForm({
          formState: { ...defaultFormState, email_auth_enabled: true },
          globalAvailability: { ...allAvailable, email_auth: false },
        });
        expect(toggles(wrapper)[0].attributes('aria-checked')).toBe('false');
      });

      it('forces the sso toggle visually off when globally unavailable, even if formState says enabled', () => {
        wrapper = mountForm({
          formState: { ...defaultFormState, sso_enabled: true },
          globalAvailability: { ...allAvailable, sso: false },
        });
        expect(toggles(wrapper)[1].attributes('aria-checked')).toBe('false');
      });
    });
  });

  // -----------------------------------------------------------------------
  // Invariant 3 — Contradiction is unexpressible
  //
  // Mode B has ZERO availability switches; Mode A has exactly the email+sso
  // switches. (Mode B switch-count is also asserted in the picker block; here
  // we pin both halves of the invariant together so the intent is explicit.)
  // -----------------------------------------------------------------------

  describe('invariant 3: contradiction is unexpressible', () => {
    it('Mode A exposes exactly the email + sso availability switches', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      expect(toggles(wrapper)).toHaveLength(2);
    });

    it('Mode B exposes zero availability switches', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      expect(toggles(wrapper)).toHaveLength(0);
    });

    it('switching into Mode B via the segment removes the switches', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      expect(toggles(wrapper)).toHaveLength(2);
      await wrapper.find('#signin-mode-one').trigger('click');
      expect(toggles(wrapper)).toHaveLength(0);
    });
  });

  // -----------------------------------------------------------------------
  // Invariant 4 — Mode-switch save semantics
  //
  // Existing tests cover: Any→clears (auto-save null), Any→null no-op, One
  // reveals picker without save. Gaps filled here:
  //   - bouncing One then Any while restrict_to stays null saves nothing
  //   - the local "intent" flag does not leak a save on its own
  // -----------------------------------------------------------------------

  describe('invariant 4: mode-switch save semantics', () => {
    it('One then Any (restrict_to never left null) emits no auto-save at all', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');
      await wrapper.find('#signin-mode-any').trigger('click');
      // Nothing was ever persisted: no method chosen, restrict_to stayed null.
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('returning to Any after picker is revealed shows Mode A again with no save', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);

      await wrapper.find('#signin-mode-any').trigger('click');
      // Back to Mode A: switches present, picker gone, still nothing saved.
      expect(toggles(wrapper)).toHaveLength(2);
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(false);
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });
  });

  // -----------------------------------------------------------------------
  // Invariant 5 — restrict_to reverting to null externally returns to Mode A
  //
  // "Reset to defaults" goes through handleDelete → emit('delete'); the parent
  // deletes the SigninConfig and restrict_to comes back null. The local
  // "intent" flag set by selectModeOne() must NOT keep the form in Mode B once
  // restrict_to is null again — a watcher clears it so the form reverts to
  // Mode A (availability fieldset shown, method picker hidden).
  // -----------------------------------------------------------------------

  describe('invariant 5: external restrict_to revert returns to Mode A', () => {
    it('reverts to Mode A when restrict_to is cleared after a method was set', async () => {
      // Start in Mode B with a method selected.
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);

      // Parent deletes the config: restrict_to returns to null.
      await wrapper.setProps({ formState: { ...defaultFormState, restrict_to: null } });

      // Form is back in Mode A: availability fieldset shown, picker gone.
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('false');
      expect(toggles(wrapper)).toHaveLength(2);
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(false);
    });

    it('reverts to Mode A when restrict_to clears after entering Mode B via the segment', async () => {
      // Enter Mode B locally (oneSelectedIntent = true) without a method set.
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);

      // A method gets picked (restrict_to set), then the config is reset to null.
      await wrapper.setProps({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      await wrapper.setProps({ formState: { ...defaultFormState, restrict_to: null } });

      // The lingering intent flag is cleared: Mode A is shown, not a stale Mode B.
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
      expect(toggles(wrapper)).toHaveLength(2);
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // ADR-024 — materialize-on-touch while following workspace defaults
  //
  // With workspaceDefault=true the form shows the SEEDED inherited state.
  // Clicking a mode/method that MATCHES that state changes nothing
  // value-wise, but must still auto-save so the composable materializes an
  // explicit override (enabled: true — the pin). With workspaceDefault=false
  // the same clicks stay no-ops (the existing early-returns).
  // -----------------------------------------------------------------------

  describe('ADR-024: materialize-on-touch (workspace default)', () => {
    it('clicking "Any" when the inherited state already matches emits an empty pin patch (pin, no value change)', async () => {
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: null, signin_enabled: true },
      });
      await wrapper.find('#signin-mode-any').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{}, 'restrict_to']);
    });

    it('clicking "Any" on an explicitly-configured domain with matching state stays a no-op (already pinned)', async () => {
      wrapper = mountForm({
        workspaceDefault: false,
        formState: { ...defaultFormState, restrict_to: null, signin_enabled: true },
      });
      await wrapper.find('#signin-mode-any').trigger('click');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('clicking "Sign-in disabled" when the inherited state is already disabled still saves signin_enabled=false (pin)', async () => {
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, signin_enabled: false },
      });
      await wrapper.find('#signin-mode-disabled').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ signin_enabled: false }, 'signin_enabled']);
    });

    it('clicking "Sign-in disabled" when already disabled on a pinned domain stays a no-op', async () => {
      wrapper = mountForm({
        workspaceDefault: false,
        formState: { ...defaultFormState, signin_enabled: false },
      });
      await wrapper.find('#signin-mode-disabled').trigger('click');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('clicking "One" when the inherited state already restricts to a method emits an empty pin patch', async () => {
      // Seeded global restrict_to pre-activates Mode B; the click changes
      // nothing value-wise but must still pin.
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: 'sso', sso_enabled: true },
      });
      await wrapper.find('#signin-mode-one').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{}, 'restrict_to']);
    });

    it('clicking "One" with no inherited restriction still only reveals the picker (nothing to pin until a method is chosen)', async () => {
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: null, signin_enabled: true },
      });
      await wrapper.find('#signin-mode-one').trigger('click');

      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('clicking the pre-checked (inherited) method radio re-saves via the click path (radios fire no change when checked)', async () => {
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: 'sso', sso_enabled: true },
      });
      // A checked radio emits click but never change; the click path must pin.
      await wrapper.find('#signin-restrict-sso').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{ restrict_to: 'sso', sso_enabled: true }, 'restrict_to']);
    });

    it('clicking the checked radio on a pinned domain does not re-save (click path is workspace-default only)', async () => {
      wrapper = mountForm({
        workspaceDefault: false,
        formState: { ...defaultFormState, restrict_to: 'sso', sso_enabled: true },
      });
      await wrapper.find('#signin-restrict-sso').trigger('click');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('clicking an UNchecked radio while workspace-default saves once, not twice (click path defers to change)', async () => {
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: 'sso', sso_enabled: true },
      });
      // Radio activation behavior: click on an unchecked radio checks it and
      // fires change — the DOM environment implements this, so triggering
      // click alone reproduces the full browser sequence (click handler
      // no-op + one change). Triggering change explicitly on top would
      // dispatch a second change event no browser ever sends.
      const radio = wrapper.find('#signin-restrict-password');
      await radio.trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted).toHaveLength(1);
      expect(emitted![0]).toEqual([{ restrict_to: 'password' }, 'restrict_to']);
    });
  });

  // -----------------------------------------------------------------------
  // No Save / no Discard button (regression guard for the redesign)
  // -----------------------------------------------------------------------

  describe('no save/discard buttons', () => {
    it('renders no Save or Discard button in Mode A', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      const saveOrDiscard = wrapper
        .findAll('button')
        .filter((b) => /save|discard/i.test(b.text()));
      expect(saveOrDiscard).toHaveLength(0);
    });

    it('renders no Save or Discard button in Mode B', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const saveOrDiscard = wrapper
        .findAll('button')
        .filter((b) => /save|discard/i.test(b.text()));
      expect(saveOrDiscard).toHaveLength(0);
    });
  });

  // -----------------------------------------------------------------------
  // Global availability gating
  // -----------------------------------------------------------------------

  describe('global availability gating', () => {
    it('omits the SSO radio in Mode B when SSO is globally off', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        globalAvailability: { ...allAvailable, sso: false },
      });
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(false);
    });

    it('omits the WebAuthn radio in Mode B when WebAuthn is globally off', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        globalAvailability: { ...allAvailable, webauthn: false },
      });
      expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(false);
    });

    it('always offers Password in Mode B even if everything else is off', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        globalAvailability: { email_auth: false, webauthn: false, sso: false },
      });
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // Reset-to-defaults (two-step) flow
  //
  // NOTE: the component renamed this surface from "Delete configuration" to
  // "Reset to defaults" (i18n keys reset_to_defaults / reset_confirm /
  // reset_keeps_sso / reset_action). The mechanism is identical — a two-step
  // confirm gated on isConfigured, internally a DELETE of the SigninConfig
  // record — and the EMITTED EVENT is still 'delete'. These tests were
  // realigned to the live copy; the contract (emit 'delete') is unchanged.
  // -----------------------------------------------------------------------

  describe('reset flow', () => {
    it('shows the reset button when isConfigured', () => {
      wrapper = mountForm({ isConfigured: true });
      const resetBtn = wrapper.findAll('button').find((b) => b.text().includes(COPY.resetToDefaults));
      expect(resetBtn).toBeTruthy();
    });

    it('does not show the reset button when not isConfigured', () => {
      wrapper = mountForm({ isConfigured: false });
      const resetBtn = wrapper.findAll('button').find((b) => b.text().includes(COPY.resetToDefaults));
      expect(resetBtn).toBeUndefined();
    });

    it('shows confirmation prompt after clicking reset', async () => {
      wrapper = mountForm({ isConfigured: true });
      const resetBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.resetToDefaults))!;
      await resetBtn.trigger('click');
      expect(wrapper.text()).toContain(COPY.resetConfirm);
    });

    it('emits delete when confirmation is accepted', async () => {
      // The button reads "Reset" but the emitted contract is still 'delete'.
      wrapper = mountForm({ isConfigured: true });
      const resetBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.resetToDefaults))!;
      await resetBtn.trigger('click');

      // Confirm button text is exactly reset_action; checking equality avoids
      // matching the now-hidden reset-to-defaults trigger.
      const confirmBtn = wrapper.findAll('button').find((b) => b.text().trim() === COPY.resetAction)!;
      await confirmBtn.trigger('click');

      expect(wrapper.emitted('delete')).toBeTruthy();
    });

    it('hides confirmation prompt when cancel is clicked', async () => {
      wrapper = mountForm({ isConfigured: true });
      const resetBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.resetToDefaults))!;
      await resetBtn.trigger('click');
      expect(wrapper.text()).toContain(COPY.resetConfirm);

      const cancelBtn = wrapper.findAll('button').find((b) => b.text().includes(COPY.cancel))!;
      await cancelBtn.trigger('click');
      expect(wrapper.text()).not.toContain(COPY.resetConfirm);
    });
  });

  // -----------------------------------------------------------------------
  // Accessibility
  // -----------------------------------------------------------------------

  describe('accessibility', () => {
    it('mode switch is a role="radiogroup"', () => {
      wrapper = mountForm();
      const group = wrapper.find('[role="radiogroup"]');
      expect(group.exists()).toBe(true);
    });

    it('mode switch segments expose role="radio"', () => {
      wrapper = mountForm();
      expect(wrapper.find('#signin-mode-any').attributes('role')).toBe('radio');
      expect(wrapper.find('#signin-mode-one').attributes('role')).toBe('radio');
    });

    it('Mode B method radios have aria-describedby linking to description', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      const radio = wrapper.find('#signin-restrict-password');
      expect(radio.attributes('aria-describedby')).toBe('signin-restrict-password-description');
    });

    it('Mode A availability toggles expose role="switch"', () => {
      wrapper = mountForm();
      expect(toggles(wrapper)).toHaveLength(2);
      toggles(wrapper).forEach((tg) => {
        expect(tg.attributes('role')).toBe('switch');
      });
    });

    it('Mode B radiogroup carries aria-describedby pointing at the picker hint', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const groups = wrapper.findAll('[role="radiogroup"]');
      // [0] = mode switch, [1] = the restrict_to method list.
      const methodGroup = groups[groups.length - 1];
      expect(methodGroup.attributes('aria-describedby')).toBe('signin-restrict-hint');
    });

    // -------------------------------------------------------------------
    // Keyboard navigation (roving tabindex)
    //
    // The radiogroup is a single tab stop: the CHECKED segment carries
    // tabindex="0", the others "-1". Arrow keys move focus between
    // segments WITHOUT selecting — activation stays on click/Enter/Space
    // (manual activation), because selecting a mode fires an auto-save
    // PUT and selection-follows-focus would write on every arrow press.
    // -------------------------------------------------------------------
    describe('keyboard navigation (roving tabindex)', () => {
      it('only the checked segment is in the tab order', () => {
        wrapper = mountForm(); // defaults to mode Any
        expect(wrapper.find('#signin-mode-any').attributes('tabindex')).toBe('0');
        expect(wrapper.find('#signin-mode-one').attributes('tabindex')).toBe('-1');
        expect(wrapper.find('#signin-mode-disabled').attributes('tabindex')).toBe('-1');
      });

      it('the tab stop follows the checked segment', () => {
        wrapper = mountForm({ formState: { ...defaultFormState, signin_enabled: false } });
        expect(wrapper.find('#signin-mode-disabled').attributes('tabindex')).toBe('0');
        expect(wrapper.find('#signin-mode-any').attributes('tabindex')).toBe('-1');
        expect(wrapper.find('#signin-mode-one').attributes('tabindex')).toBe('-1');
      });

      it('ArrowRight moves focus to the next segment without selecting', async () => {
        wrapper = mountForm();
        const any = wrapper.find('#signin-mode-any');
        (any.element as HTMLElement).focus();
        await any.trigger('keydown', { key: 'ArrowRight' });

        expect(document.activeElement?.id).toBe('signin-mode-one');
        // Focus moved, nothing selected or saved.
        expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
        expect(wrapper.emitted('auto-save')).toBeFalsy();
      });

      it('ArrowLeft wraps from the first to the last segment', async () => {
        wrapper = mountForm();
        const any = wrapper.find('#signin-mode-any');
        (any.element as HTMLElement).focus();
        await any.trigger('keydown', { key: 'ArrowLeft' });

        expect(document.activeElement?.id).toBe('signin-mode-disabled');
      });

      it('End jumps to the last segment, Home back to the first', async () => {
        wrapper = mountForm();
        const any = wrapper.find('#signin-mode-any');
        (any.element as HTMLElement).focus();
        await any.trigger('keydown', { key: 'End' });
        expect(document.activeElement?.id).toBe('signin-mode-disabled');

        await wrapper.find('#signin-mode-disabled').trigger('keydown', { key: 'Home' });
        expect(document.activeElement?.id).toBe('signin-mode-any');
      });

      it('activating a segment via keyboard (Enter→click) switches mode', async () => {
        wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
        // Native <button> fires click on Enter/Space; @vue/test-utils routes a
        // keyboard activation through the click handler.
        await wrapper.find('#signin-mode-one').trigger('keydown.enter');
        await wrapper.find('#signin-mode-one').trigger('click');
        expect(wrapper.find('#signin-mode-one').attributes('aria-checked')).toBe('true');
        expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      });
    });
  });

  // -----------------------------------------------------------------------
  // SSO Configure reachability across modes / entitlement
  //
  // Existing tests cover Mode A (button + emit, upgrade hint) and Mode B
  // (button reachable + emit). Gap: Mode B with canManageSso=false must show
  // the upgrade hint and NO Configure button, same as Mode A.
  // -----------------------------------------------------------------------

  describe('SSO configure across modes', () => {
    it('Mode B with canManageSso=false shows upgrade hint, no Configure button', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        canManageSso: false,
      });
      expect(wrapper.text()).toContain(COPY.upgradeRequired);
      const configureBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.configure) || b.text().includes(COPY.editCredentials));
      expect(configureBtn).toBeUndefined();
    });

    it('Configure label reflects ssoConfigured (Edit credentials when configured)', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        ssoConfigured: true,
        canManageSso: true,
      });
      expect(wrapper.text()).toContain(COPY.editCredentials);
    });
  });
});
