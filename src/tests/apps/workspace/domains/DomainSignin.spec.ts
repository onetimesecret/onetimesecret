// src/tests/apps/workspace/domains/DomainSignin.spec.ts
//
// Page wiring between the sign-in form, the SSO dialog and their two
// composables. The tenant-SSO verdict (`details.tenant_sso`) reads the SSO
// record, so every dialog action that can change that record (save, the
// save-and-check run that may turn it on, delete) must be followed by a
// re-read of the sign-in details; otherwise the SSO row and the dialog's
// Confirm sign-in step act on the verdict from before the change.
//
// Both composables, the form and the dialog are stubbed: what is under test
// is the page's handlers and bindings, not the children.

import { ref } from 'vue';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { TenantSsoVerdict } from '@/schemas/api/domains/responses/signin-config';
import { createTestI18n } from '@tests/setup';
import DomainSignin from '@/apps/workspace/domains/DomainSignin.vue';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  onBeforeRouteLeave: vi.fn(),
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

vi.mock('@/apps/workspace/components/domains/SsoCredentialsModal.vue', () => ({
  default: {
    name: 'SsoCredentialsModal',
    props: {
      isOpen: { type: Boolean, default: false },
      tenantSso: { type: Object, default: null },
      savedCredentialsUnchecked: { type: Boolean, default: false },
      isRefreshingLastSignIn: { type: Boolean, default: false },
    },
    emits: [
      'close',
      'save',
      'delete',
      'test',
      'diagnostics',
      'discard',
      'refresh-last-sign-in',
      'update:formState',
    ],
    template: '<div data-testid="sso-modal" />',
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
  saveConfig: vi.fn(record('saveConfig')),
  deleteConfig: vi.fn(record('deleteConfig')),
  saveAndRunDiagnostics: vi.fn(record('saveAndRunDiagnostics')),
  testConnection: vi.fn(record('testConnection')),
  discardChanges: vi.fn(record('discardChanges')),
  refreshLastSignIn: vi.fn(record('refreshLastSignIn')),
};

vi.mock('@/shared/composables/useSsoConfig', () => ({
  useSsoConfig: () => ({
    isLoading: ref(false),
    isInitialized: ref(true),
    isSaving: ref(false),
    isDeleting: ref(false),
    isTesting: ref(false),
    isDiagnosing: ref(false),
    error: ref(null),
    ssoConfig: ref(null),
    formState: ref({}),
    testResult: ref(null),
    testError: ref(''),
    diagnosticsResult: ref(null),
    savedCredentialsChecked: ref(false),
    savedCredentialsUnchecked: ref(true),
    diagnosticsError: ref(''),
    isRefreshingLastSignIn: ref(false),
    isConfigured: mockSsoConfigured,
    isEnabled: mockSsoEnabled,
    hasUnsavedChanges: ref(false),
    clientSecretMasked: ref(null),
    initialize: vi.fn(),
    ...sso,
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

  const modal = () => wrapper.getComponent({ name: 'SsoCredentialsModal' });
  const form = () => wrapper.getComponent({ name: 'DomainSigninConfigForm' });

  beforeEach(() => {
    vi.clearAllMocks();
    calls.length = 0;
    mockEntitled.value = true;
    mockTenantSso.value = null;
    mockSsoConfigured.value = true;
    mockSsoEnabled.value = false;
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  describe('re-reads the sign-in details after a dialog action that can change the SSO record', () => {
    it.each([
      ['save', 'saveConfig'],
      ['diagnostics', 'saveAndRunDiagnostics'],
      ['delete', 'deleteConfig'],
    ] as const)('%s → %s, then refreshDetails', async (event, action) => {
      wrapper = await mountPage();
      calls.length = 0;

      modal().vm.$emit(event);
      await flushPromises();

      expect(calls).toEqual([action, 'refreshDetails']);
    });

    it.each(['test', 'discard'] as const)('does not re-read after %s', async (event) => {
      wrapper = await mountPage();
      calls.length = 0;

      modal().vm.$emit(event);
      await flushPromises();

      expect(calls).not.toContain('refreshDetails');
    });

    it('skips the re-read without the sign-in entitlement (never fetched)', async () => {
      mockEntitled.value = false;
      wrapper = await mountPage();
      calls.length = 0;

      modal().vm.$emit('save');
      await flushPromises();

      expect(calls).toEqual(['saveConfig']);
    });
  });

  it('forwards a last-sign-in refresh with its passive flag', async () => {
    wrapper = await mountPage();

    modal().vm.$emit('refresh-last-sign-in', true);
    modal().vm.$emit('refresh-last-sign-in', false);
    await flushPromises();

    expect(sso.refreshLastSignIn.mock.calls).toEqual([[{ passive: true }], [{ passive: false }]]);
  });

  it('hands the same tenant-SSO verdict to the form and the dialog', async () => {
    mockTenantSso.value = { available: false, unavailable_reason: 'sso_not_permitted' };
    wrapper = await mountPage();

    expect(form().props('tenantSso')).toEqual(mockTenantSso.value);
    expect(modal().props('tenantSso')).toEqual(mockTenantSso.value);
    expect(modal().props('savedCredentialsUnchecked')).toBe(true);
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
