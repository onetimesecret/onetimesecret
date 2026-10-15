// src/tests/apps/workspace/domains/DomainSigninSso.spec.ts
//
// The SSO configuration page hosts DomainSsoConfigForm. What it owns, and
// what these tests pin, is the wiring the form cannot supply itself:
//
// - the install-wide SAML switch (SAML_ENABLED, #4604) read from the
//   bootstrap payload through features.isSamlEnabled and handed to the form
//   as samlEnabled, and the domain's verification state handed through as
//   domainVerified (#4579);
// - the re-read of the sign-in details after an action that can change the
//   SSO record (save, the save-and-check run that may turn it on, delete),
//   because the tenant-SSO verdict (`details.tenant_sso`) reads that record;
// - the return-to-window refresh of the last sign-in outcome: Confirm
//   sign-in happens in another (private) window, so when this window regains
//   focus or visibility the page re-reads it passively (no person asked);
// - the Careful Consideration Zone below the card: delete is the page's,
//   with its inline confirm, shown only once a record exists;
// - the navigation around it: back to the sign-in settings, back after a
//   successful delete, and the unsaved-changes guard on leaving and on a
//   switch to another domain's SSO page (same route, new :extid).
//
// The composables and the form are stubbed: the form's own behaviour is
// DomainSsoConfigForm.spec.ts's business.

import { ref } from 'vue';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { NavigationGuard } from 'vue-router';
import type { TenantSsoVerdict } from '@/schemas/api/domains/responses/signin-config';
import { BACKGROUND_REFRESH_THROTTLE_MS } from '@/shared/composables/useBackgroundRefresh';
import { createTestI18n } from '@tests/setup';
import DomainSigninSso from '@/apps/workspace/domains/DomainSigninSso.vue';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

const router = { push: vi.fn(), replace: vi.fn() };
let routeLeaveGuard: NavigationGuard | null = null;
let routeUpdateGuard: NavigationGuard | null = null;

vi.mock('vue-router', () => ({
  useRouter: () => router,
  onBeforeRouteLeave: (guard: NavigationGuard) => {
    routeLeaveGuard = guard;
  },
  onBeforeRouteUpdate: (guard: NavigationGuard) => {
    routeUpdateGuard = guard;
  },
}));

const isSamlEnabledMock = vi.fn<() => boolean>(() => true);
const isOrgsSsoEnabledMock = vi.fn<() => boolean>(() => true);

vi.mock('@/utils/features', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/features')>()),
  isSamlEnabled: () => isSamlEnabledMock(),
  isOrgsSsoEnabled: () => isOrgsSsoEnabledMock(),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span />' },
}));

vi.mock('@/apps/workspace/components/dashboard/DomainHeader.vue', () => ({
  default: {
    name: 'DomainHeader',
    props: {
      backVisible: { type: Boolean, default: false },
      backLabel: { type: String, default: '' },
      externalPath: { type: String, default: '' },
      hasUnsavedChanges: { type: Boolean, default: false },
    },
    emits: ['back'],
    template: '<div />',
  },
}));

vi.mock('@/shared/components/closet/SettingsSkeleton.vue', () => ({
  default: { name: 'SettingsSkeleton', template: '<div data-testid="skeleton" />' },
}));

vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    props: { error: { type: String, default: '' } },
    template: '<div data-testid="form-alert">{{ error }}</div>',
  },
}));

vi.mock('@/apps/workspace/components/domains/DomainSsoConfigForm.vue', () => ({
  default: {
    name: 'DomainSsoConfigForm',
    props: {
      domainExtId: { type: String, default: '' },
      orgId: { type: String, default: '' },
      domainHost: { type: String, default: '' },
      domainVerified: { type: Boolean, default: false },
      formState: { type: Object, default: () => ({}) },
      ssoConfig: { type: Object, default: null },
      isLoading: { type: Boolean, default: false },
      isConfigured: { type: Boolean, default: false },
      hasUnsavedChanges: { type: Boolean, default: false },
      tenantSso: { type: Object, default: null },
      diagnosticsResult: { type: Object, default: null },
      savedCredentialsChecked: { type: Boolean, default: false },
      savedCredentialsUnchecked: { type: Boolean, default: false },
      isRefreshingLastSignIn: { type: Boolean, default: false },
      samlEnabled: { type: Boolean, default: false },
    },
    emits: ['save', 'test', 'diagnostics', 'discard', 'refresh-last-sign-in', 'update:formState'],
    template: '<div data-testid="sso-form" />',
  },
}));

vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({ can: () => mockEntitled.value }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({}),
}));

vi.mock('pinia', async (importOriginal) => ({
  ...(await importOriginal<typeof import('pinia')>()),
  storeToRefs: () => ({ organizations: ref([{ extid: 'org_123' }]) }),
}));

const mockDomain = ref<{ display_domain: string; verified: boolean } | null>({
  display_domain: 'secrets.example.com',
  verified: true,
});
const mockDomainLoading = ref(false);
const mockDomainError = ref<{ message: string } | null>(null);

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: mockDomain,
    isLoading: mockDomainLoading,
    error: mockDomainError,
    initialize: vi.fn(),
  }),
}));

const mockEntitled = ref(true);
const mockTenantSso = ref<TenantSsoVerdict | null>(null);
const calls: string[] = [];
const record =
  (name: string) =>
  async (...args: unknown[]) => {
    calls.push(args.length ? `${name}:${JSON.stringify(args)}` : name);
  };

const signin = {
  refreshDetails: vi.fn(record('refreshDetails')),
  initialize: vi.fn(),
};

vi.mock('@/shared/composables/useSigninConfig', () => ({
  useSigninConfig: () => ({
    isInitialized: ref(true),
    tenantSso: mockTenantSso,
    initialize: signin.initialize,
    refreshDetails: signin.refreshDetails,
  }),
}));

const mockSsoConfig = ref<{ display_name: string } | null>(null);
const mockSsoLoading = ref(false);
const mockSsoInitialized = ref(true);
const mockSsoError = ref<{ message: string } | null>(null);
const mockSsoConfigured = ref(true);
const mockSsoSaving = ref(false);
const mockSsoDeleting = ref(false);
const mockSsoHasUnsavedChanges = ref(false);
const mockSavedCredentialsUnchecked = ref(false);
const mockSavedCredentialsChecked = ref(false);
const sso = {
  initialize: vi.fn(),
  saveConfig: vi.fn(record('saveConfig')),
  deleteConfig: vi.fn(record('deleteConfig')),
  saveAndRunDiagnostics: vi.fn(record('saveAndRunDiagnostics')),
  testConnection: vi.fn(record('testConnection')),
  discardChanges: vi.fn(record('discardChanges')),
  refreshLastSignIn: vi.fn(record('refreshLastSignIn')),
};

vi.mock('@/shared/composables/useSsoConfig', () => ({
  useSsoConfig: () => ({
    isLoading: mockSsoLoading,
    isInitialized: mockSsoInitialized,
    isSaving: mockSsoSaving,
    isDeleting: mockSsoDeleting,
    isTesting: ref(false),
    isDiagnosing: ref(false),
    error: mockSsoError,
    ssoConfig: mockSsoConfig,
    formState: ref({}),
    testResult: ref(null),
    testError: ref(''),
    diagnosticsResult: ref(null),
    savedCredentialsChecked: mockSavedCredentialsChecked,
    savedCredentialsUnchecked: mockSavedCredentialsUnchecked,
    diagnosticsError: ref(''),
    isRefreshingLastSignIn: ref(false),
    isConfigured: mockSsoConfigured,
    isEnabled: ref(false),
    hasUnsavedChanges: mockSsoHasUnsavedChanges,
    clientSecretMasked: ref(null),
    ...sso,
  }),
}));

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

const SIGNIN_ROUTE = { name: 'DomainSignin', params: { orgid: 'org_123', extid: 'dm_123' } };

describe('DomainSigninSso', () => {
  let wrapper: VueWrapper;

  const mountPage = async () => {
    const component = mount(DomainSigninSso, {
      props: { orgid: 'org_123', extid: 'dm_123' },
      global: { plugins: [createTestI18n()], stubs: { RouterLink: true } },
    });
    await flushPromises();
    return component;
  };

  const form = () => wrapper.getComponent({ name: 'DomainSsoConfigForm' });
  const header = () => wrapper.getComponent({ name: 'DomainHeader' });

  beforeEach(() => {
    vi.clearAllMocks();
    calls.length = 0;
    routeLeaveGuard = null;
    routeUpdateGuard = null;
    isSamlEnabledMock.mockReturnValue(true);
    isOrgsSsoEnabledMock.mockReturnValue(true);
    mockEntitled.value = true;
    mockTenantSso.value = null;
    mockDomain.value = { display_domain: 'secrets.example.com', verified: true };
    mockDomainLoading.value = false;
    mockDomainError.value = null;
    mockSsoConfig.value = null;
    mockSsoLoading.value = false;
    mockSsoInitialized.value = true;
    mockSsoError.value = null;
    mockSsoConfigured.value = true;
    mockSsoSaving.value = false;
    mockSsoDeleting.value = false;
    mockSsoHasUnsavedChanges.value = false;
    mockSavedCredentialsUnchecked.value = false;
    mockSavedCredentialsChecked.value = false;
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  describe('page states', () => {
    it('shows the skeleton while the record loads', async () => {
      mockSsoLoading.value = true;
      wrapper = await mountPage();

      expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-form"]').exists()).toBe(false);
    });

    it('does not wait on a record it never fetches (unentitled)', async () => {
      mockEntitled.value = false;
      mockSsoLoading.value = true;
      wrapper = await mountPage();

      expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(false);
      expect(wrapper.text()).toContain('web.domains.sso.access_denied');
      expect(sso.initialize).not.toHaveBeenCalled();
    });

    it('shows the fetch error instead of the form', async () => {
      // A failed initial GET never reaches the end of initialize.
      mockSsoInitialized.value = false;
      mockSsoError.value = { message: 'boom' };
      wrapper = await mountPage();

      expect(wrapper.get('[data-testid="form-alert"]').text()).toBe('boom');
      expect(wrapper.find('[data-testid="sso-form"]').exists()).toBe(false);
    });

    it('keeps the form (and what was typed) when an action fails after the record loaded', async () => {
      // Save, check and test share the fetch handler's onError, so a 422 or a
      // transport failure sets the same error ref. The notification and the
      // check panel report it; the form must not be replaced by the banner.
      mockSsoConfig.value = { display_name: 'Acme Entra' };
      wrapper = await mountPage();
      expect(wrapper.find('[data-testid="sso-form"]').exists()).toBe(true);

      mockSsoError.value = { message: 'secret_shape' };
      await flushPromises();

      expect(wrapper.find('[data-testid="sso-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="form-alert"]').exists()).toBe(false);
    });

    it('reads the record and the sign-in details when both gates allow it', async () => {
      wrapper = await mountPage();

      expect(sso.initialize).toHaveBeenCalledTimes(1);
      expect(signin.initialize).toHaveBeenCalledTimes(1);
    });

    it('says tenant SSO is off on this instance instead of offering a form', async () => {
      // The record is never fetched (the API would refuse), so the composable's
      // isLoading never resolves; neither the skeleton nor the form may hang
      // on it. The install flag is not an entitlement matter: no upgrade hint.
      isOrgsSsoEnabledMock.mockReturnValue(false);
      mockSsoLoading.value = true;
      mockEntitled.value = false;
      wrapper = await mountPage();

      expect(sso.initialize).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="sso-form"]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('web.domains.sso.access_denied');
      const notice = wrapper.get('[data-testid="sso-unavailable-on-instance"]');
      expect(notice.text()).toContain('web.domains.sso.unavailable_on_instance');
      expect(notice.find('router-link-stub').exists()).toBe(true);
    });
  });

  describe('header', () => {
    it('is titled with the provider display name once a record exists', async () => {
      mockSsoConfig.value = { display_name: 'Acme Entra' };
      wrapper = await mountPage();

      expect(wrapper.get('[data-testid="sso-page-heading"]').text()).toBe('Acme Entra');
    });

    it('falls back to the generic title without a record or a name', async () => {
      mockSsoConfig.value = { display_name: '  ' };
      wrapper = await mountPage();

      expect(wrapper.get('[data-testid="sso-page-heading"]').text()).toBe('web.domains.sso.title');
    });

    it('offers Back to the sign-in settings', async () => {
      wrapper = await mountPage();

      expect(header().props('backVisible')).toBe(true);
      expect(header().props('backLabel')).toBe('web.domains.sso.back_to_signin');
      expect(header().props('externalPath')).toBe('/signin');

      header().vm.$emit('back');

      expect(router.push).toHaveBeenCalledWith(SIGNIN_ROUTE);
    });
  });

  describe('props handed to the form', () => {
    it('hands the install-wide SAML switch through as samlEnabled', async () => {
      isSamlEnabledMock.mockReturnValue(false);
      wrapper = await mountPage();

      expect(isSamlEnabledMock).toHaveBeenCalled();
      expect(form().props('samlEnabled')).toBe(false);
    });

    it.each([true, false])('hands domainVerified=%s through', async (verified) => {
      mockDomain.value = { display_domain: 'secrets.example.com', verified };
      wrapper = await mountPage();

      expect(form().props('domainVerified')).toBe(verified);
      expect(form().props('domainHost')).toBe('secrets.example.com');
      expect(form().props('domainExtId')).toBe('dm_123');
      expect(form().props('orgId')).toBe('org_123');
    });

    it('hands the tenant-SSO verdict and the credential-check evidence through', async () => {
      mockTenantSso.value = { available: false, unavailable_reason: 'sso_not_permitted' };
      mockSavedCredentialsUnchecked.value = true;
      mockSavedCredentialsChecked.value = true;
      wrapper = await mountPage();

      expect(form().props('tenantSso')).toEqual(mockTenantSso.value);
      expect(form().props('savedCredentialsUnchecked')).toBe(true);
      expect(form().props('savedCredentialsChecked')).toBe(true);
      expect(form().props('diagnosticsResult')).toBeNull();
    });
  });

  describe('re-reads the sign-in details after an action that can change the SSO record', () => {
    it.each([
      ['save', 'saveConfig'],
      ['diagnostics', 'saveAndRunDiagnostics'],
    ] as const)('%s → %s, then refreshDetails', async (event, action) => {
      wrapper = await mountPage();
      calls.length = 0;

      form().vm.$emit(event);
      await flushPromises();

      expect(calls).toEqual([action, 'refreshDetails']);
    });

    it.each(['test', 'discard'] as const)('does not re-read after %s', async (event) => {
      wrapper = await mountPage();
      calls.length = 0;

      form().vm.$emit(event);
      await flushPromises();

      expect(calls).not.toContain('refreshDetails');
    });

    it('skips the re-read without the sign-in entitlement (never fetched)', async () => {
      mockEntitled.value = false;
      wrapper = await mountPage();
      calls.length = 0;

      // The unentitled page renders no form; the handler is still the one
      // under test, so drive it through the component instance.
      await (wrapper.vm as unknown as { handleSsoSave: () => Promise<void> }).handleSsoSave();

      expect(calls).toEqual(['saveConfig']);
    });
  });

  describe('Careful Consideration Zone (delete)', () => {
    const ZONE = '[data-testid="sso-caution-zone"]';
    const DELETE = '[data-testid="sso-delete"]';
    const CONFIRM = '[data-testid="sso-delete-confirm"]';
    const CANCEL = '[data-testid="sso-delete-cancel"]';
    const page = () => wrapper.get('[data-testid="domain-signin-sso-page"]');

    it('is absent while the record loads', async () => {
      mockSsoLoading.value = true;
      wrapper = await mountPage();

      expect(wrapper.find(ZONE).exists()).toBe(false);
      expect(wrapper.find('hr').exists()).toBe(false);
    });

    it('is absent when no record exists yet', async () => {
      mockSsoConfigured.value = false;
      wrapper = await mountPage();

      expect(wrapper.find('[data-testid="sso-form"]').exists()).toBe(true);
      expect(wrapper.find(ZONE).exists()).toBe(false);
      expect(wrapper.find('hr').exists()).toBe(false);
    });

    it('sits outside and after the card, under a rule, once a record exists', async () => {
      mockSsoConfig.value = { display_name: 'Acme Entra' };
      wrapper = await mountPage();

      const zone = page().get(ZONE);
      const card = page().get('[data-testid="sso-page-heading"]').element.closest('.rounded-lg')!;
      expect(card.contains(zone.element)).toBe(false);
      expect(wrapper.get('[data-testid="sso-form"]').element.contains(zone.element)).toBe(false);
      expect(card.compareDocumentPosition(zone.element) & Node.DOCUMENT_POSITION_FOLLOWING).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING
      );

      const hr = page().get('hr');
      expect(hr.classes()).toContain('my-10');
      expect(card.compareDocumentPosition(hr.element) & Node.DOCUMENT_POSITION_FOLLOWING).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING
      );
      expect(
        hr.element.compareDocumentPosition(zone.element) & Node.DOCUMENT_POSITION_FOLLOWING
      ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);

      expect(zone.attributes('aria-labelledby')).toBe('sso-caution-zone-title');
      const title = zone.get('#sso-caution-zone-title');
      expect(title.element.tagName).toBe('H2');
      expect(title.text()).toBe('web.COMMON.caution_zone');
      expect(zone.get('h3').text()).toBe('web.organizations.sso.delete_config');
      expect(zone.text()).toContain('web.organizations.sso.delete_config_hint');
      expect(zone.get(DELETE).text()).toBe('web.COMMON.delete');
      expect(zone.find(CONFIRM).exists()).toBe(false);
    });

    it('asks inline before deleting, and Cancel withdraws the question', async () => {
      wrapper = await mountPage();
      const zone = wrapper.get(ZONE);

      await zone.get(DELETE).trigger('click');
      expect(zone.text()).toContain('web.organizations.sso.delete_confirm');
      expect(zone.get(CONFIRM).text()).toBe('web.COMMON.yes_delete');
      expect(zone.get(CANCEL).text()).toBe('web.COMMON.word_cancel');
      expect(zone.find(DELETE).exists()).toBe(false);

      await zone.get(CANCEL).trigger('click');
      expect(zone.find(CONFIRM).exists()).toBe(false);
      expect(zone.find(DELETE).exists()).toBe(true);
      expect(sso.deleteConfig).not.toHaveBeenCalled();
    });

    it('Yes deletes once, re-reads the details and returns to the sign-in settings once the record is gone', async () => {
      sso.deleteConfig.mockImplementationOnce(async () => {
        calls.push('deleteConfig');
        mockSsoConfigured.value = false;
      });
      wrapper = await mountPage();
      calls.length = 0;

      await wrapper.get(DELETE).trigger('click');
      await wrapper.get(CONFIRM).trigger('click');
      await flushPromises();

      expect(sso.deleteConfig).toHaveBeenCalledTimes(1);
      expect(calls).toEqual(['deleteConfig', 'refreshDetails']);
      expect(router.push).toHaveBeenCalledWith(SIGNIN_ROUTE);
    });

    it('stays put, with the question withdrawn, when the delete did not remove the record', async () => {
      wrapper = await mountPage();
      calls.length = 0;

      await wrapper.get(DELETE).trigger('click');
      await wrapper.get(CONFIRM).trigger('click');
      await flushPromises();

      expect(sso.deleteConfig).toHaveBeenCalledTimes(1);
      expect(calls).toEqual(['deleteConfig']);
      expect(router.push).not.toHaveBeenCalled();
      expect(wrapper.find(CONFIRM).exists()).toBe(false);
      expect(wrapper.find(DELETE).exists()).toBe(true);
    });

    it('disables Delete while a delete or a save is in flight', async () => {
      mockSsoDeleting.value = true;
      wrapper = await mountPage();
      expect(wrapper.get(DELETE).attributes('disabled')).toBeDefined();

      mockSsoDeleting.value = false;
      await flushPromises();
      expect(wrapper.get(DELETE).attributes('disabled')).toBeUndefined();

      mockSsoSaving.value = true;
      await flushPromises();
      expect(wrapper.get(DELETE).attributes('disabled')).toBeDefined();
    });

    it('reads Processing on Yes while the delete is in flight', async () => {
      wrapper = await mountPage();
      await wrapper.get(DELETE).trigger('click');

      mockSsoDeleting.value = true;
      await flushPromises();

      const confirm = wrapper.get(CONFIRM);
      expect(confirm.text()).toBe('web.COMMON.processing');
      expect(confirm.attributes('disabled')).toBeDefined();
      expect(wrapper.get(CANCEL).attributes('disabled')).toBeDefined();
    });
  });

  it('relays a Refresh click as an active refresh', async () => {
    wrapper = await mountPage();

    form().vm.$emit('refresh-last-sign-in');
    await flushPromises();

    expect(sso.refreshLastSignIn.mock.calls).toEqual([[{ passive: false }]]);
  });

  describe('refresh on returning to this window', () => {
    let now = 1_000_000;

    beforeEach(() => {
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
      vi.spyOn(Date, 'now').mockImplementation(() => now);
    });

    afterEach(() => {
      vi.restoreAllMocks();
    });

    it('asks for a passive refresh when the window regains focus or visibility', async () => {
      wrapper = await mountPage();

      window.dispatchEvent(new Event('focus'));
      expect(sso.refreshLastSignIn.mock.calls).toEqual([[{ passive: true }]]);

      now += BACKGROUND_REFRESH_THROTTLE_MS * 2;
      document.dispatchEvent(new Event('visibilitychange'));
      expect(sso.refreshLastSignIn.mock.calls).toEqual([[{ passive: true }], [{ passive: true }]]);
    });

    it('asks once when focus and visibility fire together', async () => {
      wrapper = await mountPage();

      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('focus'));

      expect(sso.refreshLastSignIn).toHaveBeenCalledTimes(1);
    });

    it('does not ask while the window is hidden', async () => {
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
      wrapper = await mountPage();

      document.dispatchEvent(new Event('visibilitychange'));

      expect(sso.refreshLastSignIn).not.toHaveBeenCalled();
    });

    it('does not ask when nothing is saved yet', async () => {
      mockSsoConfigured.value = false;
      wrapper = await mountPage();

      window.dispatchEvent(new Event('focus'));

      expect(sso.refreshLastSignIn).not.toHaveBeenCalled();
    });

    it('stops listening once the page is left', async () => {
      wrapper = await mountPage();
      wrapper.unmount();

      window.dispatchEvent(new Event('focus'));

      expect(sso.refreshLastSignIn).not.toHaveBeenCalled();
    });
  });

  describe('unsaved-changes guard', () => {
    // The guards answer by return value: false cancels the navigation.
    const leave = () => {
      if (!routeLeaveGuard) throw new Error('no route-leave guard registered');
      return routeLeaveGuard({} as never, {} as never, vi.fn());
    };

    // The domain switcher keeps the route and replaces :extid. App.vue keys
    // the routed view on the fullPath, so this page would remount.
    const ssoPath = (extid: string) => `/org/org_123/domains/${extid}/signin/sso`;
    const switchDomain = () => {
      if (!routeUpdateGuard) throw new Error('no route-update guard registered');
      const at = (extid: string) =>
        ({ fullPath: ssoPath(extid), meta: {}, params: { orgid: 'org_123', extid } }) as never;
      return routeUpdateGuard(at('dm_456'), at('dm_123'), vi.fn());
    };

    it('lets a clean form leave without asking', async () => {
      const confirm = vi.spyOn(window, 'confirm');
      wrapper = await mountPage();

      expect(leave()).toBe(true);
      expect(confirm).not.toHaveBeenCalled();
    });

    it('asks before leaving unsaved edits, and stays on "cancel"', async () => {
      const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
      mockSsoHasUnsavedChanges.value = true;
      wrapper = await mountPage();

      expect(leave()).toBe(false);
      expect(confirm).toHaveBeenCalledWith('web.branding.you_have_unsaved_changes_are_you_sure');
      expect(header().props('hasUnsavedChanges')).toBe(true);
    });

    it('leaves on "ok"', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      mockSsoHasUnsavedChanges.value = true;
      wrapper = await mountPage();

      expect(leave()).toBe(true);
    });

    it('asks before switching domains with unsaved edits, and stays on "cancel"', async () => {
      const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
      mockSsoHasUnsavedChanges.value = true;
      wrapper = await mountPage();

      expect(switchDomain()).toBe(false);
      expect(confirm).toHaveBeenCalledWith('web.branding.you_have_unsaved_changes_are_you_sure');
    });

    it('switches domains on "ok"', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      mockSsoHasUnsavedChanges.value = true;
      wrapper = await mountPage();

      expect(switchDomain()).toBe(true);
    });

    it('lets a clean form switch domains without asking', async () => {
      const confirm = vi.spyOn(window, 'confirm');
      wrapper = await mountPage();

      expect(switchDomain()).toBe(true);
      expect(confirm).not.toHaveBeenCalled();
    });
  });
});
