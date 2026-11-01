// src/tests/apps/workspace/domains/DomainSignin.spec.ts
//
// Page wiring between the sign-in form and its two composables. The SSO
// credentials are edited on their own page (DomainSigninSso); this page only
// reads the SSO record's state for the form's SSO row ("Configure" /
// "Finish setup" / "Edit credentials"), sends Configure to that page, and
// forwards the retired `?modal=sso` deep link there.
//
// Both composables and the form are stubbed: what is under test is the
// page's handlers and bindings, not the children.

import { ref } from 'vue';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { TenantSsoVerdict } from '@/schemas/api/domains/responses/signin-config';
import { createTestI18n } from '@tests/setup';
import DomainSignin from '@/apps/workspace/domains/DomainSignin.vue';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

const routeQuery = ref<Record<string, string | string[]>>({});
const router = { push: vi.fn(), replace: vi.fn() };

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: routeQuery.value }),
  useRouter: () => router,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span />' },
}));

vi.mock('@/apps/workspace/components/dashboard/DomainHeader.vue', () => ({
  default: { name: 'DomainHeader', template: '<div />' },
}));

vi.mock('@/apps/workspace/components/domains/DomainAuthOverrideBanner.vue', () => ({
  default: { name: 'DomainAuthOverrideBanner', template: '<div />' },
}));

vi.mock('@/apps/workspace/components/domains/DomainSigninConfigForm.vue', () => ({
  default: {
    name: 'DomainSigninConfigForm',
    props: {
      ssoConfigured: { type: Boolean, default: false },
      ssoSetupPending: { type: Boolean, default: false },
      tenantSso: { type: Object, default: null },
    },
    emits: ['configure-sso', 'auto-save', 'delete'],
    template: '<div data-testid="signin-form" />',
  },
}));

vi.mock('@/utils/features', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/features')>()),
  isOrgsSsoEnabled: () => true,
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

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: ref({ display_domain: 'secrets.example.com', verified: true }),
    isLoading: ref(false),
    error: ref(null),
    initialize: vi.fn(),
  }),
}));

const mockEntitled = ref(true);
const mockTenantSso = ref<TenantSsoVerdict | null>(null);

const signin = {
  refreshDetails: vi.fn(),
  initialize: vi.fn(),
};

vi.mock('@/shared/composables/useSigninConfig', () => ({
  resolveGlobalMethodAvailability: () => ({ email_auth: true, webauthn: true }),
  useSigninConfig: () => ({
    isLoading: ref(false),
    isInitialized: ref(true),
    isSaving: ref(false),
    isDeleting: ref(false),
    error: ref(null),
    formState: ref({
      enabled: true,
      signin_enabled: true,
      restrict_to: null,
      email_auth_enabled: false,
      sso_enabled: false,
    }),
    savingField: ref(null),
    isConfigured: ref(true),
    hasUnsavedChanges: ref(false),
    globalEnabled: ref(true),
    effectiveEnabled: ref(true),
    isWorkspaceDefault: ref(false),
    effectiveRestrictTo: ref(null),
    tenantSso: mockTenantSso,
    initialize: signin.initialize,
    refreshDetails: signin.refreshDetails,
    autoSaveFields: vi.fn(),
    deleteConfig: vi.fn(),
  }),
}));

const mockSsoConfigured = ref(true);
const mockSsoEnabled = ref(false);
const sso = {
  initialize: vi.fn(),
};

vi.mock('@/shared/composables/useSsoConfig', () => ({
  useSsoConfig: () => ({
    isInitialized: ref(true),
    isConfigured: mockSsoConfigured,
    isEnabled: mockSsoEnabled,
    initialize: sso.initialize,
  }),
}));

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('DomainSignin', () => {
  let wrapper: VueWrapper;

  const mountPage = async () => {
    const component = mount(DomainSignin, {
      props: { orgid: 'org_123', extid: 'dm_123' },
      global: { plugins: [createTestI18n()], stubs: { RouterLink: true } },
    });
    await flushPromises();
    return component;
  };

  const form = () => wrapper.getComponent({ name: 'DomainSigninConfigForm' });

  beforeEach(() => {
    vi.clearAllMocks();
    routeQuery.value = {};
    mockEntitled.value = true;
    mockTenantSso.value = null;
    mockSsoConfigured.value = true;
    mockSsoEnabled.value = false;
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  it('sends Configure to the SSO page', async () => {
    wrapper = await mountPage();

    form().vm.$emit('configure-sso');
    await flushPromises();

    expect(router.push).toHaveBeenCalledWith({
      name: 'DomainSigninSso',
      params: { orgid: 'org_123', extid: 'dm_123' },
    });
  });

  describe('the retired `?modal=sso` deep link', () => {
    it('is replaced by the SSO page, keeping the other query params', async () => {
      routeQuery.value = { modal: 'sso', from: 'hub' };
      wrapper = await mountPage();

      expect(router.replace).toHaveBeenCalledWith({
        name: 'DomainSigninSso',
        params: { orgid: 'org_123', extid: 'dm_123' },
        query: { from: 'hub' },
      });
    });

    it('is the only query that redirects', async () => {
      routeQuery.value = { modal: 'other' };
      wrapper = await mountPage();

      expect(router.replace).not.toHaveBeenCalled();
    });

    it('does not match a repeated param', async () => {
      routeQuery.value = { modal: ['sso', 'other'] };
      wrapper = await mountPage();

      expect(router.replace).not.toHaveBeenCalled();
      expect(sso.initialize).toHaveBeenCalledTimes(1);
    });

    it('skips the page reads: the page unmounts on the next tick', async () => {
      routeQuery.value = { modal: 'sso' };
      wrapper = await mountPage();

      expect(router.replace).toHaveBeenCalledTimes(1);
      expect(signin.initialize).not.toHaveBeenCalled();
      expect(sso.initialize).not.toHaveBeenCalled();
    });
  });

  it('reads the SSO record when both tenant-SSO gates allow it', async () => {
    wrapper = await mountPage();

    expect(sso.initialize).toHaveBeenCalledTimes(1);
  });

  it('never reads the SSO record without the entitlement', async () => {
    mockEntitled.value = false;
    wrapper = await mountPage();

    expect(sso.initialize).not.toHaveBeenCalled();
  });

  it('hands the tenant-SSO verdict to the form', async () => {
    mockTenantSso.value = { available: false, unavailable_reason: 'sso_not_permitted' };
    wrapper = await mountPage();

    expect(form().props('tenantSso')).toEqual(mockTenantSso.value);
  });

  it.each([
    ['saved and off', true, false, true],
    ['saved and on', true, true, false],
    ['not saved', false, false, false],
  ])(
    'marks setup pending on the form only for a record %s',
    async (_state, configured, enabled, pending) => {
      mockSsoConfigured.value = configured;
      mockSsoEnabled.value = enabled;
      wrapper = await mountPage();

      expect(form().props('ssoConfigured')).toBe(configured);
      expect(form().props('ssoSetupPending')).toBe(pending);
    }
  );

  it('flips Finish setup off as soon as a run turns the record on', async () => {
    wrapper = await mountPage();
    expect(form().props('ssoSetupPending')).toBe(true);

    mockSsoEnabled.value = true;
    await flushPromises();

    expect(form().props('ssoSetupPending')).toBe(false);
  });
});
