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
//
// NOTE: The "One specific method" segment is offered again
// (showRestrictMode=true) now that the sign-in page honors every restrict_to
// value. DOM order is [Sign-in disabled, Any available method, One specific
// method]. Mode B is reachable both via the segment and by driving
// formState.restrict_to directly.
//
// NOTE: WebAuthn is NEVER offered in Mode B, even when globally available —
// passkeys are host-scoped (rp_id = request.host), so a passkey registered on
// the canonical host can never authenticate on a custom domain, making a
// webauthn-only restriction a dead end. The row renders (locked) only when
// restrict_to === 'webauthn' is already persisted (keep-if-selected, like the
// SSO row) with the host-scope limitation blurb. Mode A's static row is
// untouched.

import { readFileSync } from 'fs';
import { resolve } from 'path';
import { mount, type VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import DomainSigninConfigForm from '@/apps/workspace/components/domains/DomainSigninConfigForm.vue';
import type {
  EffectiveRestrictTo,
  TenantSsoVerdict,
} from '@/schemas/api/domains/responses/signin-config';
import type { SigninConfigFormState } from '@/shared/composables/useSigninConfig';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

// Tenant-SSO availability is an install feature flag (ORGS_SSO_ENABLED), read
// straight from the bootstrap — NOT a prop. It is deliberately not part of
// globalAvailability: that triple carries PLATFORM auth methods, and gating
// per-domain (tenant) SSO on the platform AUTH_SSO_ENABLED flag was the bug
// this mock exists to pin. Same gate DomainsTable/OrganizationSettings use.
const mockOrgsSsoEnabled = ref(true);
vi.mock('@/utils/features', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/features')>()),
  isOrgsSsoEnabled: () => mockOrgsSsoEnabled.value,
}));

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

/** Resolve a key with named interpolation, as the component does. */
const tp = (key: string, params: Record<string, string>) => i18n.global.t(key, params);

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
  connectionDisabledBadge: t('web.domains.sso.connection_disabled_badge'),
  connectionDisabledHint: t('web.domains.sso.connection_disabled_hint'),
  // Tenant-SSO status line (#4111)
  statusActiveBadge: t('web.domains.sso.status_active_badge'),
  statusActiveHint: t('web.domains.sso.status_active_hint'),
  statusNotConfiguredBadge: t('web.domains.sso.status_not_configured_badge'),
  statusNotPermittedBadge: t('web.domains.sso.status_not_permitted_badge'),
  statusAuthDisabledBadge: t('web.domains.sso.status_auth_disabled_badge'),
  statusUnsupportedProviderBadge: t('web.domains.sso.status_unsupported_provider_badge'),
  statusUnavailableBadge: t('web.domains.sso.status_unavailable_badge'),
  statusUnavailableHint: t('web.domains.sso.status_unavailable_hint'),
  // SSO-restriction lockout guard (#4111)
  ssoRestrictWarningTitle: t('web.domains.signin.sso_restrict_warning_title'),
  ssoRestrictWarningBody: t('web.domains.signin.sso_restrict_warning_body'),
  // Resolved-restriction notices — interpolated exactly as the component does,
  // so the {method} placeholder is verified as substituted, not printed.
  restrictionUnavailableSso: tp('web.domains.signin.restriction_unavailable_notice', {
    method: t('web.domains.signin.method_sso'),
  }),
  restrictionConflictPassword: tp('web.domains.signin.restriction_conflict_notice', {
    method: t('web.domains.signin.method_password'),
  }),
  restrictionUnavailableUnknown: t('web.domains.signin.restriction_unavailable_unknown_notice'),
  methodWebauthnUnavailable: t('web.domains.signin.method_webauthn_unavailable'),
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

const allAvailable = { email_auth: true, webauthn: true };

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
  /**
   * The server's tenant-SSO verdict (#4111, `details.tenant_sso`). Left
   * undefined ⇒ the prop is omitted, which must render no status line and arm
   * no guard: the client has no verdict and may not invent one (ADR-024).
   */
  tenantSso?: TenantSsoVerdict | null;
  /**
   * The server's restriction resolution
   * (ADR-034#resolution-is-model-owned / #settings-api-serializes-effective-restrict-to).
   */
  effectiveRestrictTo?: EffectiveRestrictTo | null;
  canManageSso?: boolean;
  globalAvailability?: { email_auth: boolean; webauthn: boolean };
  /** ORGS_SSO_ENABLED — tenant-SSO availability (bootstrap flag, not a prop). */
  orgsSsoEnabled?: boolean;
  savingField?: keyof SigninConfigFormState | null;
}

function mountForm(opts: MountOptions = {}): VueWrapper {
  mockOrgsSsoEnabled.value = opts.orgsSsoEnabled ?? true;
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
      // Omitted (not defaulted) when unset, so the no-verdict case — an older
      // backend, or details not loaded — stays observable.
      ...(opts.tenantSso !== undefined ? { tenantSso: opts.tenantSso } : {}),
      ...(opts.effectiveRestrictTo !== undefined
        ? { effectiveRestrictTo: opts.effectiveRestrictTo }
        : {}),
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
      expect(wrapper.find('#signin-mode-disabled').attributes('aria-checked')).toBe('false');
    });

    it('renders the Mode B segment checked and the restrict picker when restrict_to is set', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      const one = wrapper.find('#signin-mode-one');
      expect(one.exists()).toBe(true);
      expect(one.attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('false');
    });

    it('gives the checked Mode B segment the tab stop (roving tabindex)', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });

      // Exactly one segment is in the tab order — the checked one.
      expect(wrapper.find('#signin-mode-one').attributes('tabindex')).toBe('0');
      expect(wrapper.find('#signin-mode-disabled').attributes('tabindex')).toBe('-1');
      expect(wrapper.find('#signin-mode-any').attributes('tabindex')).toBe('-1');
    });

    it('exposes exactly one checked radio in the mode radiogroup for active Mode B', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });

      const radiogroup = wrapper.find('[role="radiogroup"]');
      const checked = radiogroup.findAll('[role="radio"]').filter(
        (r) => r.attributes('aria-checked') === 'true'
      );
      expect(checked).toHaveLength(1);
      expect(checked[0].attributes('id')).toBe('signin-mode-one');

      // The sr-only stand-in (which represented active Mode B while the
      // segment was withheld) must not render alongside the real segment —
      // it would double-announce the selection.
      expect(wrapper.find('#signin-mode-one-active').exists()).toBe(false);
    });

    it('does not render the Mode B stand-in radio when Mode B is not active', () => {
      // The sr-only stand-in only exists to represent an otherwise-unrepresentable
      // active Mode B (showRestrictMode=false). In Mode A the "Any" segment
      // carries aria-checked itself.
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      expect(wrapper.find('#signin-mode-one-active').exists()).toBe(false);

      const radiogroup = wrapper.find('[role="radiogroup"]');
      const checked = radiogroup.findAll('[role="radio"]').filter(
        (r) => r.attributes('aria-checked') === 'true'
      );
      expect(checked).toHaveLength(1);
      expect(checked[0].attributes('id')).toBe('signin-mode-any');
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

    it('clicking "One specific method" reveals the picker without saving (no method picked yet)', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');

      // The local intent flag switches the view to Mode B; nothing persists
      // until a method is actually chosen.
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('picking a method after entering Mode B saves restrict_to with its availability flag', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');
      await wrapper.find('#signin-restrict-email_auth').trigger('change');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([
        { restrict_to: 'email_auth', email_auth_enabled: true },
        'restrict_to',
      ]);
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

    it('renders the disabled segment (first) in the mode switch', () => {
      wrapper = mountForm();
      expect(wrapper.find('#signin-mode-disabled').exists()).toBe(true);
      expect(wrapper.find('#signin-mode-disabled').attributes('role')).toBe('radio');
    });

    it('is checked when signin_enabled is false', () => {
      wrapper = mountForm({ formState: disabledFormState });
      expect(wrapper.find('#signin-mode-disabled').attributes('aria-checked')).toBe('true');
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('false');
    });

    it('wins over a preserved restrict_to for display', () => {
      wrapper = mountForm({ formState: { ...disabledFormState, restrict_to: 'sso' } });
      expect(wrapper.find('#signin-mode-disabled').attributes('aria-checked')).toBe('true');
      // Mode B's picker must not render while disabled, even with a restriction.
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(false);
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

    it('re-enabling via "One specific method" persists signin_enabled=true immediately', async () => {
      // From disabled, entering Mode B must bring sign-in back on even before
      // a method is picked (a preserved restrict_to restores that method).
      wrapper = mountForm({ formState: { ...disabledFormState, restrict_to: 'sso' } });
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

    it('hides Configure when ORGS_SSO_ENABLED is off, even with the entitlement', () => {
      // The tenant-SSO write endpoints enforce BOTH gates, so an entitled org
      // on an install with tenant SSO off would open a modal whose save is
      // rejected with "Organization SSO is not enabled on this instance".
      wrapper = mountForm({ canManageSso: true, orgsSsoEnabled: false });
      const configureBtn = wrapper.findAll('button').find((b) => b.text().includes(COPY.configure));
      expect(configureBtn).toBeUndefined();
    });

    it('does not blame the plan when the blocker is the install flag', () => {
      // "Upgrade to configure" would name the wrong cause — no plan unlocks an
      // operator's ORGS_SSO_ENABLED. The row's hint carries the real reason.
      wrapper = mountForm({ canManageSso: true, orgsSsoEnabled: false });
      expect(wrapper.text()).not.toContain(COPY.upgradeRequired);
      expect(wrapper.find('#signin-sso-hint').text()).toContain(COPY.availabilityUnavailable);
    });
  });

  // -----------------------------------------------------------------------
  // Entitlement gating — SSO controls lock when !canManageSso
  //
  // Without the manage-SSO entitlement the org cannot configure SSO
  // credentials, so SSO can never activate on the domain. An operable
  // "Enabled" toggle next to the "Upgrade to configure" lock contradicted
  // that (and persisted a flag that could never take effect).
  //
  // The lock is expressed by :disabled ONLY. :enabled still reports the
  // stored value — manage_sso governs who may configure tenant SSO, not
  // whether it runs, so blanking the toggle would misreport a domain whose
  // SSO is live.
  // -----------------------------------------------------------------------

  describe('entitlement gating: canManageSso=false locks SSO controls', () => {
    it('disables the sso availability toggle in Mode A', () => {
      wrapper = mountForm({ canManageSso: false });
      expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
    });

    it('still reports the stored sso value while locked (disabled, not blanked)', () => {
      wrapper = mountForm({
        canManageSso: false,
        formState: { ...defaultFormState, sso_enabled: true },
      });
      expect(toggles(wrapper)[1].attributes('aria-checked')).toBe('true');
      expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
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
    it('renders a radio for each offerable method (webauthn excluded by design)', () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'password' } });
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(true);
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
      // Host-scoped passkeys can never work webauthn-only on a custom domain,
      // so the row is withheld even though webauthn is globally available.
      expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(false);
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
  // Invariant 1 — Availability-flag flip on Mode B selection
  //
  // The existing "mode B: restrict_to picker" block covers Email (+flag),
  // SSO (+flag), and Password (no flag). Passkeys can no longer be PICKED at
  // all (host-scoped rp_id — see the webauthn lockout block below), so the
  // former "picking Passkeys auto-saves restrict_to: webauthn" case is
  // structurally impossible: its radio never renders unless already persisted,
  // and then only disabled.
  // -----------------------------------------------------------------------

  describe('invariant 1: Mode B selection flips availability flag', () => {
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
      it('offers password/email/sso when everything is globally available — never webauthn', () => {
        wrapper = mountForm({
          formState: { ...defaultFormState, restrict_to: 'password' },
          globalAvailability: allAvailable,
        });
        expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
        expect(wrapper.find('#signin-restrict-email_auth').exists()).toBe(true);
        expect(wrapper.find('#signin-restrict-sso').exists()).toBe(true);
        // Global availability is irrelevant for webauthn in Mode B: passkeys
        // are host-scoped, so the row only appears when already persisted.
        expect(wrapper.find('#signin-restrict-webauthn').exists()).toBe(false);
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
          globalAvailability: { email_auth: false, webauthn: false },
          orgsSsoEnabled: false,
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

      it('disables the sso toggle and shows "Unavailable" reason when ORGS_SSO_ENABLED is off', () => {
        wrapper = mountForm({ orgsSsoEnabled: false });
        expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
        expect(wrapper.find('#signin-sso-hint').text()).toContain(COPY.availabilityUnavailable);
      });

      it('shows "Allow on this domain" reason for sso when available', () => {
        wrapper = mountForm({ orgsSsoEnabled: true });
        expect(wrapper.find('#signin-sso-hint').text()).toContain(COPY.allowOnDomain);
      });

      it('keeps the sso toggle operable when platform SSO is off but ORGS_SSO_ENABLED is on', () => {
        // The axis fix: bootstrap `features.sso` (platform AUTH_SSO_ENABLED,
        // resolved against the workspace host) must have NO bearing on the
        // tenant-SSO toggle. It is no longer a prop at all, so an install with
        // platform SSO off leaves this toggle live.
        wrapper = mountForm({ orgsSsoEnabled: true, canManageSso: true });
        expect(toggles(wrapper)[1].attributes('disabled')).toBeUndefined();
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

      it('reports the STORED sso value even when the management gates are off', () => {
        // NOT the email AND-semantics case. email_auth_enabled is ANDed with a
        // real install kill switch, so `stored && global` IS its effective
        // state. Tenant SSO is different: the runtime ladder
        // (SsoConfig.tenant_sso_unavailable_reason) gates on the SsoConfig
        // record and sso_permitted_for? — never on ORGS_SSO_ENABLED or
        // manage_sso, which only govern who may CONFIGURE it. A domain whose
        // stored sso_enabled is true is running tenant SSO right now, so the
        // toggle must not render OFF and misreport persisted state. It stays
        // disabled (see :disabled), just truthful.
        wrapper = mountForm({
          formState: { ...defaultFormState, sso_enabled: true },
          orgsSsoEnabled: false,
          canManageSso: false,
        });
        expect(toggles(wrapper)[1].attributes('aria-checked')).toBe('true');
        expect(toggles(wrapper)[1].attributes('disabled')).toBeDefined();
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

    it('Mode B entered via the segment (no method picked yet) shows zero availability switches', async () => {
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');
      expect(toggles(wrapper)).toHaveLength(0);
    });
  });

  // -----------------------------------------------------------------------
  // Invariant 4 — Mode-switch save semantics
  //
  // The "One specific method" intent flag must never leak a save on its own:
  // covered in the "mode switch" block above (clicking the segment reveals
  // the picker without saving; only picking a method persists).
  // -----------------------------------------------------------------------

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
      // Start in Mode B with a method selected (segment is hidden, but an
      // existing restriction still renders the picker).
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);

      // Parent deletes the config: restrict_to returns to null.
      await wrapper.setProps({ formState: { ...defaultFormState, restrict_to: null } });

      // Form is back in Mode A: availability fieldset shown, picker gone.
      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
      expect(toggles(wrapper)).toHaveLength(2);
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(false);
    });

    it('reverts to Mode A when restrict_to is cleared after entering Mode B via the segment', async () => {
      // Enter Mode B with the intent flag (no method picked), let the parent
      // set and then clear a restriction: the watcher must clear the lingering
      // intent so the form lands back in Mode A, not a picker with nothing
      // selected.
      wrapper = mountForm({ formState: { ...defaultFormState, restrict_to: null } });
      await wrapper.find('#signin-mode-one').trigger('click');
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);

      await wrapper.setProps({ formState: { ...defaultFormState, restrict_to: 'sso' } });
      await wrapper.setProps({ formState: { ...defaultFormState, restrict_to: null } });

      expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
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

    it('clicking "One" when the inherited state already restricts emits an empty pin patch', async () => {
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: 'sso', signin_enabled: true },
      });
      await wrapper.find('#signin-mode-one').trigger('click');

      const emitted = wrapper.emitted('auto-save');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual([{}, 'restrict_to']);
    });

    it('clicking "One" while following defaults with no inherited restriction does not save', async () => {
      // With restrict_to null there is nothing to pin yet — the picker opens
      // and persistence waits for an actual method choice.
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: null, signin_enabled: true },
      });
      await wrapper.find('#signin-mode-one').trigger('click');
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
    it('omits the SSO radio in Mode B when ORGS_SSO_ENABLED is off', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        orgsSsoEnabled: false,
      });
      expect(wrapper.find('#signin-restrict-sso').exists()).toBe(false);
    });

    it('keeps the SSO radio visible-but-locked when it is the CURRENT restriction', () => {
      // Omitting the selected method would render a radiogroup with nothing
      // checked, hiding the fact that the domain is restricted to SSO.
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        orgsSsoEnabled: false,
      });
      const radio = wrapper.find('#signin-restrict-sso');
      expect(radio.exists()).toBe(true);
      expect((radio.element as HTMLInputElement).checked).toBe(true);
      expect(radio.attributes('disabled')).toBeDefined();
    });

    it('cannot re-select SSO from the locked row', async () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        orgsSsoEnabled: false,
      });
      await wrapper.find('#signin-restrict-sso').trigger('change');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
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
        globalAvailability: { email_auth: false, webauthn: false },
        orgsSsoEnabled: false,
      });
      expect(wrapper.find('#signin-restrict-password').exists()).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // WebAuthn lockout — host-scoped passkeys (rp_id = request.host)
  //
  // A passkey registered on the canonical sign-in host can never authenticate
  // on a custom domain, so restrict_to=webauthn is a guaranteed dead end.
  // Mode B therefore never OFFERS the method; a domain where it is already
  // persisted gets the keep-if-selected treatment (visible, checked, locked)
  // so the radiogroup still reports the true configuration — mirroring the
  // unentitled-SSO row. Mode A's static row is deliberately untouched.
  // -----------------------------------------------------------------------

  describe('webauthn lockout (host-scoped passkeys)', () => {
    it('keeps the WebAuthn radio visible-but-locked when it is the CURRENT restriction', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'webauthn' },
      });
      const radio = wrapper.find('#signin-restrict-webauthn');
      expect(radio.exists()).toBe(true);
      expect((radio.element as HTMLInputElement).checked).toBe(true);
      expect(radio.attributes('disabled')).toBeDefined();
    });

    it('shows the host-scope limitation blurb on the locked row', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'webauthn' },
      });
      expect(wrapper.find('#signin-restrict-webauthn-description').text()).toContain(
        COPY.methodWebauthnUnavailable
      );
    });

    it('cannot re-select WebAuthn from the locked row', async () => {
      // Belt & suspenders like the SSO case: the disabled attribute blocks the
      // event AND selectMethod hard-returns on 'webauthn'; this test fails
      // only if both regress.
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'webauthn' },
      });
      await wrapper.find('#signin-restrict-webauthn').trigger('change');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('does not materialize a save via onMethodClick (ADR-024) on the locked row', async () => {
      // While following workspace defaults, clicking a pre-checked radio
      // routes through selectMethod to pin the inherited config — the
      // webauthn guard must stop that path too.
      wrapper = mountForm({
        workspaceDefault: true,
        formState: { ...defaultFormState, restrict_to: 'webauthn' },
      });
      await wrapper.find('#signin-restrict-webauthn').trigger('click');
      expect(wrapper.emitted('auto-save')).toBeFalsy();
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
      expect(wrapper.find('#signin-mode-disabled').attributes('role')).toBe('radio');
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
        expect(wrapper.find('#signin-mode-disabled').attributes('tabindex')).toBe('-1');
      });

      it('the tab stop follows the checked segment', () => {
        wrapper = mountForm({ formState: { ...defaultFormState, signin_enabled: false } });
        expect(wrapper.find('#signin-mode-disabled').attributes('tabindex')).toBe('0');
        expect(wrapper.find('#signin-mode-any').attributes('tabindex')).toBe('-1');
      });

      // Three visible segments, in order
      // [signin-mode-disabled, signin-mode-any, signin-mode-one].
      it('ArrowRight from the last segment wraps to the first without selecting', async () => {
        wrapper = mountForm(); // defaults to mode Any
        const one = wrapper.find('#signin-mode-one');
        (one.element as HTMLElement).focus();
        await one.trigger('keydown', { key: 'ArrowRight' });

        expect(document.activeElement?.id).toBe('signin-mode-disabled');
        // Focus moved, nothing selected or saved.
        expect(wrapper.find('#signin-mode-any').attributes('aria-checked')).toBe('true');
        expect(wrapper.emitted('auto-save')).toBeFalsy();
      });

      it('ArrowLeft moves focus to the previous segment', async () => {
        wrapper = mountForm();
        const any = wrapper.find('#signin-mode-any');
        (any.element as HTMLElement).focus();
        await any.trigger('keydown', { key: 'ArrowLeft' });

        expect(document.activeElement?.id).toBe('signin-mode-disabled');
      });

      it('End jumps to the last segment, Home back to the first', async () => {
        wrapper = mountForm();
        const disabled = wrapper.find('#signin-mode-disabled');
        (disabled.element as HTMLElement).focus();
        await disabled.trigger('keydown', { key: 'End' });
        expect(document.activeElement?.id).toBe('signin-mode-one');

        await wrapper.find('#signin-mode-one').trigger('keydown', { key: 'Home' });
        expect(document.activeElement?.id).toBe('signin-mode-disabled');
      });

      it('activating a segment via keyboard (Enter→click) switches mode', async () => {
        wrapper = mountForm(); // defaults to mode Any, signin_enabled: true
        // Native <button> fires click on Enter/Space; @vue/test-utils routes a
        // keyboard activation through the click handler. State is prop-controlled,
        // so the auto-save emit — not a local aria-checked flip — is the
        // observable effect of activating "Sign-in disabled".
        await wrapper.find('#signin-mode-disabled').trigger('keydown.enter');
        await wrapper.find('#signin-mode-disabled').trigger('click');

        const emitted = wrapper.emitted('auto-save');
        expect(emitted).toBeTruthy();
        expect(emitted![0]).toEqual([{ signin_enabled: false }, 'signin_enabled']);
      });
    });
  });

  // -----------------------------------------------------------------------
  // SSO Configure reachability across modes / entitlement
  //
  // Existing tests cover Mode A (button + emit, upgrade hint) and Mode B
  // (button reachable + emit). Gap: Mode B with canManageSso=false must show
  // the upgrade hint and NO Configure button, same as Mode A. And like Mode A,
  // Configure needs BOTH write-endpoint gates: restrict_to='sso' keeps the SSO
  // row visible when ORGS_SSO_ENABLED is off (visible-but-locked invariant),
  // so its Configure button must not survive on canManageSso alone — the modal
  // save would be rejected ("Organization SSO is not enabled on this
  // instance").
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

    it('Mode B hides Configure when ORGS_SSO_ENABLED is off, even with the entitlement — and does not blame the plan', () => {
      // Mirror of Mode A's wrong-blame guard: "Upgrade to configure" would
      // name the wrong cause — no plan unlocks an operator's ORGS_SSO_ENABLED.
      // With the entitlement present and only the install flag off, the locked
      // SSO row renders neither the button nor the upgrade hint.
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        canManageSso: true,
        orgsSsoEnabled: false,
      });
      const configureBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.configure) || b.text().includes(COPY.editCredentials));
      expect(configureBtn).toBeUndefined();
      expect(wrapper.text()).not.toContain(COPY.upgradeRequired);
    });

    it('Mode B with both gates off hides Configure and keeps the upgrade hint', () => {
      // Deliberate v-else-if="!canManageSso" semantics: the hint keys on the
      // entitlement alone, so it still shows when the install flag is ALSO off
      // — acceptable, because the entitlement is genuinely missing too and an
      // upgrade is a real (if not sufficient) step toward configuring.
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        canManageSso: false,
        orgsSsoEnabled: false,
      });
      const configureBtn = wrapper
        .findAll('button')
        .find((b) => b.text().includes(COPY.configure) || b.text().includes(COPY.editCredentials));
      expect(configureBtn).toBeUndefined();
      expect(wrapper.text()).toContain(COPY.upgradeRequired);
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

  // -----------------------------------------------------------------------
  // Tenant-SSO status line (#4111)
  //
  // Supersedes the #4107 dormant-credentials indicator. The blocking rung is
  // computed once by the server (SsoConfig.tenant_sso_unavailable_reason) and
  // arrives as `details.tenant_sso`; this form maps the reported rung to copy
  // and derives nothing (ADR-024). The render sites and the
  // connection-disabled copy carry over — only the condition's source swapped.
  //
  // Still gated on ssoConfigurable: the remedial copy points at controls
  // ("Edit credentials", the SSO toggle) that only render with both write
  // gates, and without them the row already names the real blocker.
  // -----------------------------------------------------------------------

  describe('tenant-SSO status line (#4111)', () => {
    const STATUS = '[data-testid="sso-tenant-status"]';
    const COMPACT = '[data-testid="sso-tenant-status-compact"]';

    const verdict = (reason: string | null): TenantSsoVerdict => ({
      available: reason === null,
      unavailable_reason: reason,
    });

    it('renders nothing when the response carries no verdict', () => {
      // Older backend, or details not yet loaded. The client has no verdict
      // and must not invent one from ssoConfigured / the policy toggle.
      wrapper = mountForm({ ssoConfigured: true });
      expect(wrapper.find(STATUS).exists()).toBe(false);
      expect(wrapper.find(COMPACT).exists()).toBe(false);
    });

    it('reports Active when the server says tenant SSO is available', () => {
      wrapper = mountForm({ ssoConfigured: true, tenantSso: verdict(null) });
      const status = wrapper.find(STATUS);
      expect(status.exists()).toBe(true);
      expect(status.text()).toContain(COPY.statusActiveBadge);
      expect(status.text()).toContain(COPY.statusActiveHint);
      expect(status.text()).not.toContain('web.domains.sso.status_active');
    });

    it('reports the connection-disabled rung with the copy carried over from #4107', () => {
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: verdict('sso_config_disabled'),
      });
      const status = wrapper.find(STATUS);
      expect(status.text()).toContain(COPY.connectionDisabledBadge);
      expect(status.text()).toContain(COPY.connectionDisabledHint);
      expect(status.text()).not.toContain('web.domains.sso.connection_disabled');
    });

    it('reports "Not configured" for the no_sso_config rung — even with credentials claimed present', () => {
      // ssoConfigured is a UI convenience for the Configure/Edit button label;
      // it is NOT the availability source. The verdict wins.
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: verdict('no_sso_config'),
      });
      expect(wrapper.find(STATUS).text()).toContain(COPY.statusNotConfiguredBadge);
    });

    it.each([
      ['sso_not_permitted', 'statusNotPermittedBadge'],
      ['auth_disabled', 'statusAuthDisabledBadge'],
      ['unsupported_provider_type', 'statusUnsupportedProviderBadge'],
    ] as const)('reports the %s rung', (reason, copyKey) => {
      wrapper = mountForm({ ssoConfigured: true, tenantSso: verdict(reason) });
      expect(wrapper.find(STATUS).text()).toContain(COPY[copyKey]);
    });

    it('falls back to generic unavailable copy for a rung this version does not know', () => {
      // The rung list is a backend enumeration; a newer one must degrade to
      // "unavailable", never to silence.
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: verdict('some_future_rung'),
      });
      const status = wrapper.find(STATUS);
      expect(status.text()).toContain(COPY.statusUnavailableBadge);
      expect(status.text()).toContain(COPY.statusUnavailableHint);
    });

    it('falls back to generic unavailable copy when unavailable with no reason given', () => {
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: null },
      });
      expect(wrapper.find(STATUS).text()).toContain(COPY.statusUnavailableBadge);
    });

    it('does not render without the manage-SSO entitlement — the actions it points at are absent', () => {
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: verdict('sso_config_disabled'),
        canManageSso: false,
      });
      expect(wrapper.find(STATUS).exists()).toBe(false);

      wrapper.unmount();
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        ssoConfigured: true,
        tenantSso: verdict('sso_config_disabled'),
        canManageSso: false,
      });
      expect(wrapper.find(COMPACT).exists()).toBe(false);
    });

    it('does not render when tenant SSO is off install-wide (ORGS_SSO_ENABLED)', () => {
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: verdict('sso_config_disabled'),
        orgsSsoEnabled: false,
      });
      expect(wrapper.find(STATUS).exists()).toBe(false);
    });

    it('renders the compact status on the SSO radio row in Mode B', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        ssoConfigured: true,
        tenantSso: verdict('sso_config_disabled'),
      });
      const compact = wrapper.find(COMPACT);
      expect(compact.exists()).toBe(true);
      // Mode A's row (and its status line) is not in the tree at all.
      expect(wrapper.find(STATUS).exists()).toBe(false);
      // The reason is TEXT, not just a tooltip — a title attribute is neither
      // keyboard- nor screen-reader-reliable.
      expect(compact.text()).toContain(COPY.connectionDisabledBadge);
      expect(compact.text()).toContain(COPY.connectionDisabledHint);
    });

    it('announces the status rather than conveying it by colour alone', () => {
      wrapper = mountForm({
        ssoConfigured: true,
        tenantSso: verdict('sso_config_disabled'),
      });
      expect(wrapper.find(STATUS).attributes('role')).toBe('status');
    });
  });

  // -----------------------------------------------------------------------
  // SSO-restriction lockout guard (#4111 / ADR-034#resolution-intersects-never-widens)
  //
  // A restriction that cannot be honoured fails CLOSED: restricting a domain
  // to SSO while the server reports tenant SSO unavailable takes the host
  // dark. The form auto-saves, so the warning has to land BEFORE the PUT —
  // nothing is emitted until "Restrict anyway".
  // -----------------------------------------------------------------------

  describe('SSO-restriction lockout guard (#4111)', () => {
    const WARNING = '[data-testid="sso-restriction-lockout-warning"]';
    const CONFIRM = '[data-testid="sso-restriction-lockout-confirm"]';
    const CANCEL = '[data-testid="sso-restriction-lockout-cancel"]';

    /** Mode B with the SSO radio present and pickable. */
    const modeB = { ...defaultFormState, restrict_to: 'password' as const };

    it('warns instead of saving when tenant SSO is unavailable', async () => {
      wrapper = mountForm({
        formState: modeB,
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'sso_config_disabled' },
      });

      await wrapper.find('#signin-restrict-sso').trigger('change');

      expect(wrapper.emitted('auto-save')).toBeFalsy();
      const warning = wrapper.find(WARNING);
      expect(warning.exists()).toBe(true);
      expect(warning.attributes('role')).toBe('alert');
      expect(warning.text()).toContain(COPY.ssoRestrictWarningTitle);
      expect(warning.text()).toContain(COPY.ssoRestrictWarningBody);
      // The radio stays unchecked: formState was never touched.
      expect(
        (wrapper.find('#signin-restrict-sso').element as HTMLInputElement).checked
      ).toBe(false);
    });

    it('does not warn when selecting SSO atomically resolves sso_not_permitted', async () => {
      wrapper = mountForm({
        formState: { ...modeB, sso_enabled: false },
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'sso_not_permitted' },
      });

      await wrapper.find('#signin-restrict-sso').trigger('change');

      expect(wrapper.find(WARNING).exists()).toBe(false);
      expect(wrapper.emitted('auto-save')![0]).toEqual([
        { restrict_to: 'sso', sso_enabled: true },
        'restrict_to',
      ]);
    });

    it('still warns for sso_not_permitted when SSO is already enabled', async () => {
      wrapper = mountForm({
        formState: { ...modeB, sso_enabled: true },
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'sso_not_permitted' },
      });

      await wrapper.find('#signin-restrict-sso').trigger('change');

      expect(wrapper.emitted('auto-save')).toBeFalsy();
      expect(wrapper.find(WARNING).exists()).toBe(true);
    });

    it('does NOT fire when the server reports tenant SSO available', async () => {
      wrapper = mountForm({
        formState: modeB,
        ssoConfigured: true,
        tenantSso: { available: true, unavailable_reason: null },
      });

      await wrapper.find('#signin-restrict-sso').trigger('change');

      expect(wrapper.find(WARNING).exists()).toBe(false);
      expect(wrapper.emitted('auto-save')![0]).toEqual([
        { restrict_to: 'sso', sso_enabled: true },
        'restrict_to',
      ]);
    });

    it('does NOT fire when no verdict was serialized', async () => {
      // No claim from the server means no guard — the client may not
      // manufacture an availability verdict of its own (ADR-024).
      wrapper = mountForm({ formState: modeB, ssoConfigured: true });

      await wrapper.find('#signin-restrict-sso').trigger('change');

      expect(wrapper.find(WARNING).exists()).toBe(false);
      expect(wrapper.emitted('auto-save')).toBeTruthy();
    });

    it('saves the restriction once confirmed', async () => {
      wrapper = mountForm({
        formState: modeB,
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'no_sso_config' },
      });

      await wrapper.find('#signin-restrict-sso').trigger('change');
      await wrapper.find(CONFIRM).trigger('click');

      expect(wrapper.emitted('auto-save')![0]).toEqual([
        { restrict_to: 'sso', sso_enabled: true },
        'restrict_to',
      ]);
      expect(wrapper.find(WARNING).exists()).toBe(false);
    });

    it('cancelling dismisses the warning and saves nothing', async () => {
      wrapper = mountForm({
        formState: modeB,
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'no_sso_config' },
      });

      await wrapper.find('#signin-restrict-sso').trigger('change');
      await wrapper.find(CANCEL).trigger('click');

      expect(wrapper.find(WARNING).exists()).toBe(false);
      expect(wrapper.emitted('auto-save')).toBeFalsy();
    });

    it('guards the materialize-on-touch path too (workspace default, SSO pre-selected)', async () => {
      // Clicking an already-checked radio while following workspace defaults
      // still persists a pin (ADR-024) — that write is the same lockout.
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        workspaceDefault: true,
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'sso_config_disabled' },
      });

      await wrapper.find('#signin-restrict-sso').trigger('click');

      expect(wrapper.emitted('auto-save')).toBeFalsy();
      expect(wrapper.find(WARNING).exists()).toBe(true);
    });

    it('does not guard non-SSO methods', async () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        ssoConfigured: true,
        tenantSso: { available: false, unavailable_reason: 'sso_config_disabled' },
      });

      await wrapper.find('#signin-restrict-password').trigger('change');

      expect(wrapper.find(WARNING).exists()).toBe(false);
      expect(wrapper.emitted('auto-save')![0]).toEqual([{ restrict_to: 'password' }, 'restrict_to']);
    });
  });

  // -----------------------------------------------------------------------
  // Resolved-restriction notice
  // (ADR-034#resolution-is-model-owned / #resolution-intersects-never-widens)
  //
  // `unavailable` and `source: 'conflict'` are states a method picker cannot
  // express: the restriction stands, but nothing satisfies it, so sign-in is
  // closed. Both are server-resolved and rendered verbatim — the client never
  // recomputes them from global_restrict_to and the raw flags.
  // -----------------------------------------------------------------------

  describe('resolved-restriction notice (#4111 / ADR-024)', () => {
    const NOTICE = '[data-testid="signin-restriction-notice"]';

    const resolution = (r: Partial<EffectiveRestrictTo>): EffectiveRestrictTo => ({
      state: 'restricted',
      restrict_to: null,
      source: 'domain',
      ...r,
    });

    it('names the method that cannot run when the restriction is unavailable', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        effectiveRestrictTo: resolution({
          state: 'unavailable',
          restrict_to: 'sso',
          source: 'domain',
        }),
      });
      const notice = wrapper.find(NOTICE);
      expect(notice.exists()).toBe(true);
      expect(notice.attributes('role')).toBe('status');
      expect(notice.text()).toContain(COPY.restrictionUnavailableSso);
      expect(notice.text()).not.toContain('web.domains.signin.restriction_unavailable');
    });

    it('explains a conflict as a conflict, not as one side winning', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'sso' },
        effectiveRestrictTo: resolution({
          state: 'unavailable',
          restrict_to: 'password',
          source: 'conflict',
        }),
      });
      const notice = wrapper.find(NOTICE);
      // The GLOBAL method (the one still in force) is named, and the copy
      // says the two sides disagree rather than showing one as the winner.
      expect(notice.text()).toContain(COPY.restrictionConflictPassword);
    });

    it('falls back to unnamed copy when the resolved method is unrecognized', () => {
      // A persisted value this version cannot parse degrades restrict_to to
      // null while `state` keeps carrying the truth.
      wrapper = mountForm({
        effectiveRestrictTo: resolution({
          state: 'unavailable',
          restrict_to: null,
          source: 'domain',
        }),
      });
      expect(wrapper.find(NOTICE).text()).toContain(COPY.restrictionUnavailableUnknown);
    });

    it('renders nothing for a healthy restriction or an unrestricted domain', () => {
      wrapper = mountForm({
        formState: { ...defaultFormState, restrict_to: 'password' },
        effectiveRestrictTo: resolution({
          state: 'restricted',
          restrict_to: 'password',
          source: 'domain',
        }),
      });
      expect(wrapper.find(NOTICE).exists()).toBe(false);

      wrapper.unmount();
      wrapper = mountForm({
        effectiveRestrictTo: resolution({ state: 'unrestricted', source: 'global' }),
      });
      expect(wrapper.find(NOTICE).exists()).toBe(false);
    });

    it('renders nothing when no resolution was serialized', () => {
      wrapper = mountForm({});
      expect(wrapper.find(NOTICE).exists()).toBe(false);
    });
  });
});
