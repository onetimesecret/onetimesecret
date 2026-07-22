// src/tests/apps/workspace/account/ConnectedIdentities.spec.ts

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import { createTestI18n } from '@tests/setup';
import type { ConnectedIdentity } from '@/schemas/api/auth/responses/auth';
import type { IdentityErrorCode } from '@/shared/composables/useConnectedIdentities';

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
import type { SsoProvider } from '@/utils/features';
const mockGetSsoProviders = vi.fn<() => SsoProvider[]>(() => []);
vi.mock('@/utils/features', () => ({
  getSsoProviders: () => mockGetSsoProviders(),
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

  const mountComponent = () =>
    mount(ConnectedIdentities, {
      global: {
        plugins: [i18n, createTestingPinia({ createSpy: vi.fn })],
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

    it('excludes a provider already present in identities (same route_name)', () => {
      mockState.identities.value = [makeIdentity({ provider: 'entra' })];
      mockGetSsoProviders.mockReturnValue(providers);
      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="connections-connect-oidc"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="connections-connect-entra"]').exists()).toBe(false);
    });

    it('renders no connect region when every provider is already linked', () => {
      mockState.identities.value = [makeIdentity({ provider: 'entra' })];
      mockGetSsoProviders.mockReturnValue([{ route_name: 'entra', display_name: 'Microsoft Entra' }]);
      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="connections-connect"]').exists()).toBe(false);
    });

    it('initiates SSO connect with the provider route, shrimp, and return redirect', async () => {
      mockGetSsoProviders.mockReturnValue([{ route_name: 'oidc', display_name: 'OpenID Connect' }]);
      wrapper = mountComponent();

      await wrapper.find('[data-testid="connections-connect-oidc"]').trigger('click');

      expect(mockSubmitSsoLogin).toHaveBeenCalledWith({
        routeName: 'oidc',
        shrimp: 'test-shrimp',
        redirect: '/account/settings/security/connections',
      });
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

      await wrapper.find('[data-testid="connections-error"] button[aria-label="Dismiss"]').trigger('click');
      expect(mockState.clearError).toHaveBeenCalled();
    });
  });
});
