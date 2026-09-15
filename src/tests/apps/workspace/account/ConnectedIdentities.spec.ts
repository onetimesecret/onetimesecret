// src/tests/apps/workspace/account/ConnectedIdentities.spec.ts

import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import type { IdentityErrorCode } from '@/shared/composables/useConnectedIdentities';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/account/settings/security/connections' })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Mock OIcon
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock SettingsLayout
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: {
    name: 'SettingsLayout',
    template: '<div class="mock-settings-layout"><slot /></div>',
  },
}));

// Mock ListSkeleton
vi.mock('@/shared/components/closet/ListSkeleton.vue', () => ({
  default: {
    name: 'ListSkeleton',
    template: '<div class="mock-list-skeleton" />',
    props: ['icon', 'iconSize'],
  },
}));

// Mock ConfirmDialog — expose confirm/cancel buttons that emit the events the
// component wires to useConfirmDialog's confirm()/cancel().
vi.mock('@/shared/components/modals/ConfirmDialog.vue', () => ({
  default: {
    name: 'ConfirmDialog',
    template: `<div class="mock-confirm-dialog">
      <button class="confirm-btn" @click="$emit('confirm')">confirm</button>
      <button class="cancel-btn" @click="$emit('cancel')">cancel</button>
    </div>`,
    props: ['title', 'message', 'type'],
    emits: ['confirm', 'cancel'],
  },
}));

// Mock the composable — controllable reactive state + spies.
const mockState = {
  identities: ref<ConnectedIdentity[]>([]),
  isLoading: ref(false),
  error: ref<string | null>(null),
  errorCode: ref<IdentityErrorCode>(null),
  fetchIdentities: vi.fn(),
  removeIdentity: vi.fn(),
  clearError: vi.fn(),
};

vi.mock('@/shared/composables/useConnectedIdentities', () => ({
  useConnectedIdentities: () => mockState,
}));

// Configured SSO providers (bootstrap-backed in prod) — controllable per test.
// Partial mock: only getSsoProviders is stubbed. providerLabel and
// configuredProviderLabel stay real so the deliberate precedence split between
// them (built-in map vs. operator display_name) is exercised, not stubbed away.
import type { SsoProvider } from '@/utils/features';
const mockGetSsoProviders = vi.fn<() => SsoProvider[]>(() => []);
// Sessions "related settings" link is gated on AUTH_ACTIVE_SESSIONS_ENABLED.
const mockActiveSessionsEnabled = ref(false);
vi.mock('@/utils/features', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/features')>()),
  getSsoProviders: () => mockGetSsoProviders(),
  isActiveSessionsEnabledOf: () => mockActiveSessionsEnabled.value,
}));

// SSO connect initiates a form POST (navigates away); assert the call, not nav.
const mockSubmitSsoLogin = vi.fn();
vi.mock('@/shared/utils/sso', () => ({
  submitSsoLogin: (opts: unknown) => mockSubmitSsoLogin(opts),
}));

// CSRF store: the component reads csrfStore.shrimp to include in the connect POST.
vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => ({ shrimp: 'test-shrimp' }),
}));

import ConnectedIdentities from '@/apps/workspace/account/ConnectedIdentities.vue';

const i18n = createTestI18n();

const makeIdentity = (overrides: Partial<ConnectedIdentity> = {}): ConnectedIdentity => ({
  id: 1,
  provider: 'entra',
  issuer: 'https://login.microsoftonline.com/tenant/v2.0',
  uid: 'abcd…wxyz',
  ...overrides,
});

/**
 * ConnectedIdentities Component Tests (#3840 Phase 2)
 *
 * Verifies the SSO account-linking panel:
 * - fetches the identity list on mount
 * - renders loading / empty / list states
 * - masks nothing itself (backend supplies a masked uid) and hides the '' issuer
 * - drives per-row removal through a confirmation dialog
 * - surfaces generic and last-credential (409) errors distinctly
 */
describe('ConnectedIdentities', () => {
  let wrapper: VueWrapper;

  // The Connect surface is read from bootstrap domain_strategy (#4412):
  // 'canonical' (the store default) is the platform surface, 'custom' a
  // tenant host. Tests that care pass it explicitly.
  const mountComponent = (domainStrategy = 'canonical') =>
    mount(ConnectedIdentities, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: { bootstrap: { domain_strategy: domainStrategy } },
          }),
        ],
      },
    });

  beforeEach(() => {
    vi.clearAllMocks();
    mockState.identities.value = [];
    mockState.isLoading.value = false;
    mockState.error.value = null;
    mockState.errorCode.value = null;
    mockState.fetchIdentities.mockResolvedValue([]);
    mockState.removeIdentity.mockResolvedValue(true);
    // clearAllMocks keeps implementations, so reset the provider list explicitly.
    mockGetSsoProviders.mockReturnValue([]);
    mockActiveSessionsEnabled.value = false;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  describe('Basic Rendering', () => {
    it('renders within SettingsLayout', () => {
      wrapper = mountComponent();
      expect(wrapper.find('.mock-settings-layout').exists()).toBe(true);
    });

    it('renders page title', () => {
      wrapper = mountComponent();
      const title = wrapper.find('h1');
      expect(title.exists()).toBe(true);
      expect(title.text()).toBe('web.auth.connections.title');
    });

    it('fetches identities on mount', () => {
      wrapper = mountComponent();
      expect(mockState.fetchIdentities).toHaveBeenCalledTimes(1);
    });
  });

  describe('Loading State', () => {
    it('shows the list skeleton while loading with no identities yet', () => {
      mockState.isLoading.value = true;
      wrapper = mountComponent();
      expect(wrapper.find('.mock-list-skeleton').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-empty"]').exists()).toBe(false);
    });
  });

  describe('Empty State', () => {
    it('shows empty state when there are no identities', () => {
      wrapper = mountComponent();
      const empty = wrapper.find('[data-testid="connections-empty"]');
      expect(empty.exists()).toBe(true);
      expect(empty.text()).toContain('web.auth.connections.no_identities');
    });

    it('does not render the list when empty', () => {
      wrapper = mountComponent();
      expect(wrapper.find('[data-testid="connections-list"]').exists()).toBe(false);
    });
  });

  describe('List Rendering', () => {
    it('renders one row per identity', () => {
      mockState.identities.value = [
        makeIdentity({ id: 1 }),
        makeIdentity({ id: 2, provider: 'github', issuer: '', uid: '***' }),
      ];
      wrapper = mountComponent();

      const rows = wrapper.findAll('[data-testid="connections-list"] > li');
      expect(rows).toHaveLength(2);
    });

    it('shows a friendly provider label', () => {
      mockState.identities.value = [makeIdentity({ provider: 'entra' })];
      wrapper = mountComponent();
      expect(wrapper.text()).toContain('Microsoft Entra');
    });

    it('falls back to a capitalized provider name for unknown providers', () => {
      mockState.identities.value = [makeIdentity({ provider: 'okta' })];
      wrapper = mountComponent();
      expect(wrapper.text()).toContain('Okta');
    });

    it('shows the backend-masked uid verbatim', () => {
      mockState.identities.value = [makeIdentity({ uid: 'abcd…wxyz' })];
      wrapper = mountComponent();
      expect(wrapper.text()).toContain('abcd…wxyz');
    });

    it('shows the issuer when present', () => {
      mockState.identities.value = [
        makeIdentity({ issuer: 'https://login.microsoftonline.com/tenant/v2.0' }),
      ];
      wrapper = mountComponent();
      expect(wrapper.text()).toContain('https://login.microsoftonline.com/tenant/v2.0');
    });

    it('hides the issuer for the empty-string sentinel (legacy / OAuth2-only rows)', () => {
      mockState.identities.value = [makeIdentity({ provider: 'github', issuer: '', uid: '***' })];
      wrapper = mountComponent();
      expect(wrapper.text()).not.toContain('web.auth.connections.issuer');
    });
  });

  describe('Remove Flow', () => {
    it('reveals the confirmation dialog when Remove is clicked', async () => {
      mockState.identities.value = [makeIdentity({ id: 7 })];
      wrapper = mountComponent();

      expect(wrapper.find('.mock-confirm-dialog').exists()).toBe(false);

      await wrapper.find('[data-testid="connections-remove-7"]').trigger('click');
      await flushPromises();

      expect(wrapper.find('.mock-confirm-dialog').exists()).toBe(true);
    });

    it('calls removeIdentity with the row id when confirmed', async () => {
      mockState.identities.value = [makeIdentity({ id: 7 })];
      wrapper = mountComponent();

      await wrapper.find('[data-testid="connections-remove-7"]').trigger('click');
      await flushPromises();
      await wrapper.find('.confirm-btn').trigger('click');
      await flushPromises();

      expect(mockState.removeIdentity).toHaveBeenCalledWith(7);
    });

    it('does not call removeIdentity when the dialog is canceled', async () => {
      mockState.identities.value = [makeIdentity({ id: 7 })];
      wrapper = mountComponent();

      await wrapper.find('[data-testid="connections-remove-7"]').trigger('click');
      await flushPromises();
      await wrapper.find('.cancel-btn').trigger('click');
      await flushPromises();

      expect(mockState.removeIdentity).not.toHaveBeenCalled();
    });
  });

  describe('Connect a provider', () => {
    const providers: SsoProvider[] = [
      { route_name: 'oidc', display_name: 'OpenID Connect' },
      { route_name: 'entra', display_name: 'Microsoft Entra' },
    ];

    it('renders a Connect button for each connectable provider', () => {
      mockGetSsoProviders.mockReturnValue(providers);
      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="connections-connect"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-entra"]').exists()).toBe(true);
    });

    it('offers connect buttons in the empty state', () => {
      mockGetSsoProviders.mockReturnValue([{ route_name: 'oidc', display_name: 'OpenID Connect' }]);
      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="connections-empty"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
    });

    it('excludes a provider already present in identities on the platform surface (exact known link)', () => {
      // Platform providers come from env, so a route name resolves to exactly
      // one IdP and a matching row is authoritative evidence of the link.
      mockState.identities.value = [makeIdentity({ provider: 'entra' })];
      mockGetSsoProviders.mockReturnValue(providers);
      wrapper = mountComponent('canonical');

      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-entra"]').exists()).toBe(false);
    });

    it('renders no connect region when every provider is already linked on the platform surface', () => {
      mockState.identities.value = [makeIdentity({ provider: 'entra' })];
      mockGetSsoProviders.mockReturnValue([
        { route_name: 'entra', display_name: 'Microsoft Entra' },
      ]);
      wrapper = mountComponent('canonical');

      expect(wrapper.find('[data-testid="connections-connect"]').exists()).toBe(false);
    });

    it('initiates SSO connect with the provider route, shrimp, return redirect, and connect intent', async () => {
      mockGetSsoProviders.mockReturnValue([{ route_name: 'oidc', display_name: 'OpenID Connect' }]);
      wrapper = mountComponent();

      await wrapper.find('[data-testid="connections-connect-oidc"]').trigger('click');

      expect(mockSubmitSsoLogin).toHaveBeenCalledWith({
        routeName: 'oidc',
        shrimp: 'test-shrimp',
        redirect: '/account/settings/security/connections',
        connect: true,
      });
    });
  });

  /**
   * The tenant callback resolves the complete identity tuple. The masked rows
   * available to this component cannot prove that a configured tenant route is
   * already linked, even when its route name and issuer match.
   */
  describe('Connect on a tenant surface', () => {
    const TENANT_ISSUER = 'https://login.microsoftonline.com/tenant-a/v2.0';
    const tenantOidc: SsoProvider = { route_name: 'oidc', display_name: 'Acme SSO' };

    it('keeps a matching route visible when the stored identity has another issuer', () => {
      mockState.identities.value = [
        makeIdentity({ provider: 'oidc', issuer: 'https://platform-idp.example/v2.0' }),
      ];
      mockGetSsoProviders.mockReturnValue([tenantOidc]);
      wrapper = mountComponent('custom');

      expect(wrapper.find('[data-testid="connections-list"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
    });

    it('keeps a matching route and issuer visible because masked uids are not evidence', () => {
      mockState.identities.value = [
        makeIdentity({ id: 1, provider: 'oidc', issuer: TENANT_ISSUER, uid: 'aaaa…1111' }),
        makeIdentity({ id: 2, provider: 'oidc', issuer: TENANT_ISSUER, uid: 'bbbb…2222' }),
      ];
      mockGetSsoProviders.mockReturnValue([tenantOidc]);
      wrapper = mountComponent('custom');

      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
    });

    it('keeps every configured tenant route connectable', () => {
      mockState.identities.value = [makeIdentity({ provider: 'entra' })];
      mockGetSsoProviders.mockReturnValue([
        { route_name: 'entra', display_name: 'Contoso' },
        tenantOidc,
      ]);
      wrapper = mountComponent('custom');

      expect(wrapper.find('[data-testid="connections-connect-entra"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
    });

    it('submits an explicit Connect initiation for a route already represented in stored identities', async () => {
      mockState.identities.value = [makeIdentity({ provider: 'oidc', issuer: TENANT_ISSUER })];
      mockGetSsoProviders.mockReturnValue([tenantOidc]);
      wrapper = mountComponent('custom');

      await wrapper.find('[data-testid="connections-connect-oidc"]').trigger('click');

      expect(mockSubmitSsoLogin).toHaveBeenCalledWith({
        routeName: 'oidc',
        shrimp: 'test-shrimp',
        redirect: '/account/settings/security/connections',
        connect: true,
      });
    });
  });

  /**
   * Label precedence with PRODUCTION display_name values.
   *
   * The fixtures above use display_name: 'OpenID Connect', which happens to match
   * the built-in map and therefore cannot tell the two precedences apart. A stock
   * deployment (OIDC_ISSUER + OIDC_CLIENT_ID, no OIDC_DISPLAY_NAME) ships the
   * generic default 'SSO' / 'Microsoft' instead — the values that expose the
   * split. Linked rows must stay canonical; connect buttons must honour the
   * operator's name. Needs an i18n with a real interpolating message, since the
   * shared pass-through i18n renders the bare key.
   */
  describe('Provider label precedence (stock backend display_name defaults)', () => {
    const stockProviders: SsoProvider[] = [
      { route_name: 'oidc', display_name: 'SSO' },
      { route_name: 'entra', display_name: 'Microsoft' },
    ];

    const interpolatingI18n = createI18n({
      legacy: false,
      locale: 'en',
      missingWarn: false,
      fallbackWarn: false,
      missing: (_: unknown, key: string) => key,
      messages: {
        en: { web: { auth: { connections: { connect_action: 'Connect {provider}' } } } } as never,
      },
    });

    const mountWithI18n = () =>
      mount(ConnectedIdentities, {
        global: {
          plugins: [interpolatingI18n, createTestingPinia({ createSpy: vi.fn })],
        },
      });

    it('labels a linked row canonically, ignoring the generic display_name', () => {
      mockState.identities.value = [
        makeIdentity({ id: 1, provider: 'oidc' }),
        makeIdentity({ id: 2, provider: 'entra' }),
      ];
      mockGetSsoProviders.mockReturnValue(stockProviders);
      wrapper = mountWithI18n();

      const list = wrapper.find('[data-testid="connections-list"]').text();
      expect(list).toContain('OpenID Connect');
      expect(list).toContain('Microsoft Entra');
    });

    it('labels the connect button with the operator display_name', () => {
      mockGetSsoProviders.mockReturnValue(stockProviders);
      wrapper = mountWithI18n();

      expect(wrapper.find('[data-testid="connections-connect-oidc"]').text()).toContain(
        'Connect SSO'
      );
      expect(wrapper.find('[data-testid="connections-connect-entra"]').text()).toContain(
        'Connect Microsoft'
      );
    });

    it('falls back to the canonical label when display_name is blank', () => {
      mockGetSsoProviders.mockReturnValue([{ route_name: 'oidc', display_name: '' }]);
      wrapper = mountWithI18n();

      expect(wrapper.find('[data-testid="connections-connect-oidc"]').text()).toContain(
        'Connect OpenID Connect'
      );
    });
  });

  describe('Related settings', () => {
    // The component does not import RouterLink, so <router-link> renders as a
    // bare custom element here; assert on its `to` attribute.
    const hasLinkTo = (path: string) => wrapper.find(`[to="${path}"]`).exists();
    const SESSIONS_PATH = '/account/settings/security/sessions';

    it('links to Sessions when the active sessions feature is enabled', () => {
      mockActiveSessionsEnabled.value = true;
      wrapper = mountComponent();
      expect(hasLinkTo(SESSIONS_PATH)).toBe(true);
    });

    it('omits the Sessions link when the feature is disabled (route guard would dead-end)', () => {
      mockActiveSessionsEnabled.value = false;
      wrapper = mountComponent();
      expect(hasLinkTo(SESSIONS_PATH)).toBe(false);
      // Sibling passkeys link is unaffected.
      expect(hasLinkTo('/account/settings/security/passkeys')).toBe(true);
    });
  });

  describe('Error Display', () => {
    it('shows a generic error with alert role', () => {
      mockState.error.value = 'web.auth.connections.errors.generic';
      wrapper = mountComponent();

      const err = wrapper.find('[data-testid="connections-error"]');
      expect(err.exists()).toBe(true);
      expect(err.attributes('role')).toBe('alert');
      expect(err.classes()).toContain('bg-red-50');
    });

    it('styles the last-credential guard as a warning, not an error', () => {
      mockState.error.value = 'web.auth.connections.errors.last_credential';
      mockState.errorCode.value = 'last_credential';
      wrapper = mountComponent();

      const err = wrapper.find('[data-testid="connections-error"]');
      expect(err.exists()).toBe(true);
      expect(err.classes()).toContain('bg-yellow-50');
      expect(err.classes()).not.toContain('bg-red-50');
    });

    it('calls clearError when the dismiss button is clicked', async () => {
      mockState.error.value = 'web.auth.connections.errors.generic';
      wrapper = mountComponent();

      await wrapper
        .find('[data-testid="connections-error"] button[aria-label="Dismiss"]')
        .trigger('click');
      expect(mockState.clearError).toHaveBeenCalled();
    });
  });
});
