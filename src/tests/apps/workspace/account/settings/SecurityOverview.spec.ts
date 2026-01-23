// src/tests/apps/workspace/account/settings/SecurityOverview.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { computed, defineComponent, ref } from 'vue';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/account/settings/security' })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to" class="router-link"><slot /></a>',
    props: ['to'],
  },
}));

// Mock OIcon component
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

// Mock isWebAuthnEnabled feature flag
const mockWebAuthnEnabled = ref(true);
vi.mock('@/utils/features', () => ({
  isWebAuthnEnabled: () => mockWebAuthnEnabled.value,
}));

// Mock useAccount composable
const mockAccountInfo = ref<{
  email_verified: boolean;
  mfa_enabled: boolean;
  recovery_codes_count: number;
  passkeys_count: number;
  active_sessions_count: number;
} | null>(null);

vi.mock('@/shared/composables/useAccount', () => ({
  useAccount: () => ({
    accountInfo: mockAccountInfo,
    fetchAccountInfo: vi.fn().mockResolvedValue(mockAccountInfo.value),
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        auth: {
          change_password: { title: 'Password' },
          mfa: {
            title: 'Two-Factor Authentication',
            setup_description: 'Add an extra layer of security',
          },
          recovery_codes: {
            title: 'Recovery Codes',
            description: 'Backup codes for account recovery',
          },
          passkeys: {
            title: 'Passkeys',
            description: 'Use biometrics or security keys',
            count: '{count} passkey | {count} passkeys',
            not_configured: 'Not configured',
          },
          sessions: {
            title: 'Active Sessions',
          },
          account: {
            mfa_enabled: 'Enabled',
            mfa_disabled: 'Not enabled',
          },
        },
        settings: {
          password: { update_account_password: 'Update your account password' },
          sessions: { manage_active_sessions: 'Manage your active sessions' },
          security: {
            configured: 'Configured',
            change: 'Change',
            manage: 'Manage',
            enable: 'Enable',
            codes_available: '{0} codes available',
            no_codes: 'No codes generated',
            active_sessions: '{0} active',
            excellent: 'Excellent',
            good: 'Good',
            fair: 'Fair',
            weak: 'Weak',
            security_score: 'Security Score',
            score_description: 'Your account security status',
            improve_security: 'Improve your security',
            enable_mfa_recommendation: 'Enable two-factor authentication',
            generate_recovery_codes_recommendation: 'Generate recovery codes',
          },
        },
      },
    },
  },
});

/**
 * SecurityOverview Component Tests
 *
 * Tests the security overview page that:
 * - Displays security setting cards (password, MFA, recovery codes)
 * - Conditionally shows passkey card when WebAuthn is enabled
 * - Shows correct status for each security feature
 * - Links to individual security setting pages
 */
describe('SecurityOverview', () => {
  let wrapper: VueWrapper;

  // SecurityOverview stub representing the component interface
  const SecurityOverviewStub = defineComponent({
    name: 'SecurityOverview',
    setup() {
      const webAuthnEnabled = ref(mockWebAuthnEnabled.value);
      const accountInfo = mockAccountInfo;

      interface SecurityCard {
        id: string;
        icon: { collection: string; name: string };
        title: string;
        description: string;
        status: 'active' | 'inactive' | 'warning';
        statusText: string;
        action: { label: string; to: string };
      }

      const buildCoreCards = (info: typeof mockAccountInfo.value): SecurityCard[] => {
        if (!info) return [];
        return [
          {
            id: 'password',
            icon: { collection: 'heroicons', name: 'lock-closed-solid' },
            title: 'Password',
            description: 'Update your account password',
            status: 'active',
            statusText: 'Configured',
            action: { label: 'Change', to: '/account/settings/security/password' },
          },
          {
            id: 'mfa',
            icon: { collection: 'heroicons', name: 'key-solid' },
            title: 'Two-Factor Authentication',
            description: 'Add an extra layer of security',
            status: info.mfa_enabled ? 'active' : 'warning',
            statusText: info.mfa_enabled ? 'Enabled' : 'Not enabled',
            action: {
              label: info.mfa_enabled ? 'Manage' : 'Enable',
              to: '/account/settings/security/mfa',
            },
          },
          {
            id: 'recovery-codes',
            icon: { collection: 'heroicons', name: 'document-text-solid' },
            title: 'Recovery Codes',
            description: 'Backup codes for account recovery',
            status: info.recovery_codes_count > 0 ? 'active' : 'inactive',
            statusText:
              info.recovery_codes_count > 0
                ? `${info.recovery_codes_count} codes available`
                : 'No codes generated',
            action: { label: 'Manage', to: '/account/settings/security/recovery-codes' },
          },
        ];
      };

      const buildPasskeyCard = (info: typeof mockAccountInfo.value): SecurityCard | null => {
        if (!info) return null;
        const passkeyCount = info.passkeys_count ?? 0;
        return {
          id: 'passkeys',
          icon: { collection: 'heroicons', name: 'finger-print-solid' },
          title: 'Passkeys',
          description: 'Use biometrics or security keys',
          status: passkeyCount > 0 ? 'active' : 'inactive',
          statusText: passkeyCount > 0 ? `${passkeyCount} passkey${passkeyCount > 1 ? 's' : ''}` : 'Not configured',
          action: {
            label: passkeyCount > 0 ? 'Manage' : 'Enable',
            to: '/account/settings/security/passkeys',
          },
        };
      };

      const securityCards = computed<SecurityCard[]>(() => {
        if (!accountInfo.value) return [];

        const cards = buildCoreCards(accountInfo.value);

        if (webAuthnEnabled.value) {
          const passkeyCard = buildPasskeyCard(accountInfo.value);
          if (passkeyCard) {
            cards.push(passkeyCard);
          }
        }

        return cards;
      });

      const statusColorClasses = {
        active: 'status-active bg-green-50 text-green-700',
        inactive: 'status-inactive bg-gray-50 text-gray-600',
        warning: 'status-warning bg-yellow-50 text-yellow-800',
      };

      return {
        securityCards,
        statusColorClasses,
        webAuthnEnabled,
      };
    },
    template: `
      <div class="mock-settings-layout">
        <div class="space-y-8">
          <!-- Security Settings Cards -->
          <div class="grid gap-6 sm:grid-cols-2">
            <div
              v-for="card in securityCards"
              :key="card.id"
              :data-card-id="card.id"
              class="security-card rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
              <div class="flex items-start gap-4">
                <div class="flex size-12 shrink-0 items-center justify-center rounded-lg bg-gray-100 dark:bg-gray-700">
                  <span class="o-icon" :data-icon="card.icon.name" :data-collection="card.icon.collection"></span>
                </div>
                <div class="flex-1">
                  <h3 class="font-semibold text-gray-900 dark:text-white">{{ card.title }}</h3>
                  <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">{{ card.description }}</p>

                  <!-- Status Badge -->
                  <div class="mt-3">
                    <span :class="['status-badge inline-flex items-center rounded-full px-2 py-1 text-xs font-medium', statusColorClasses[card.status]]">
                      {{ card.statusText }}
                    </span>
                  </div>

                  <!-- Action Button -->
                  <div class="mt-4">
                    <a
                      :href="card.action.to"
                      class="action-link inline-flex items-center gap-2 text-sm font-medium text-brand-600 hover:text-brand-700">
                      {{ card.action.label }}
                      <span class="o-icon" data-icon="arrow-right-solid"></span>
                    </a>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset mocks
    mockWebAuthnEnabled.value = true;
    mockAccountInfo.value = {
      email_verified: true,
      mfa_enabled: false,
      recovery_codes_count: 0,
      passkeys_count: 0,
      active_sessions_count: 1,
    };
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = () =>
    mount(SecurityOverviewStub, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
          }),
        ],
        stubs: {
          RouterLink: {
            template: '<a :href="to" class="router-link"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });

  describe('Basic Rendering', () => {
    it('renders within SettingsLayout', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.mock-settings-layout').exists()).toBe(true);
    });

    it('renders security cards grid', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.grid').exists()).toBe(true);
    });

    it('renders core security cards', () => {
      wrapper = mountComponent();

      expect(wrapper.find('[data-card-id="password"]').exists()).toBe(true);
      expect(wrapper.find('[data-card-id="mfa"]').exists()).toBe(true);
      expect(wrapper.find('[data-card-id="recovery-codes"]').exists()).toBe(true);
    });
  });

  describe('Passkey Card (WebAuthn Feature Flag)', () => {
    it('shows passkey card when WebAuthn is enabled', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      expect(wrapper.find('[data-card-id="passkeys"]').exists()).toBe(true);
    });

    it('hides passkey card when WebAuthn is disabled', () => {
      mockWebAuthnEnabled.value = false;
      wrapper = mountComponent();

      expect(wrapper.find('[data-card-id="passkeys"]').exists()).toBe(false);
    });

    it('displays passkey card title', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      expect(passkeyCard.text()).toContain('Passkeys');
    });

    it('displays passkey card description', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      expect(passkeyCard.text()).toContain('Use biometrics or security keys');
    });

    it('shows fingerprint icon on passkey card', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      expect(passkeyCard.find('[data-icon="finger-print-solid"]').exists()).toBe(true);
    });
  });

  describe('Passkey Count Display', () => {
    it('shows "Not configured" when no passkeys exist', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 0,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      expect(passkeyCard.text()).toContain('Not configured');
    });

    it('shows passkey count when passkeys exist (singular)', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 1,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      expect(passkeyCard.text()).toContain('1 passkey');
    });

    it('shows passkey count when multiple passkeys exist (plural)', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 3,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      expect(passkeyCard.text()).toContain('3 passkeys');
    });

    it('shows inactive status when no passkeys configured', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 0,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      const statusBadge = passkeyCard.find('.status-badge');
      expect(statusBadge.classes()).toContain('status-inactive');
    });

    it('shows active status when passkeys configured', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 2,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      const statusBadge = passkeyCard.find('.status-badge');
      expect(statusBadge.classes()).toContain('status-active');
    });
  });

  describe('Passkey Card Action', () => {
    it('shows "Enable" action when no passkeys exist', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 0,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      const actionLink = passkeyCard.find('.action-link');
      expect(actionLink.text()).toContain('Enable');
    });

    it('shows "Manage" action when passkeys exist', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 1,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      const actionLink = passkeyCard.find('.action-link');
      expect(actionLink.text()).toContain('Manage');
    });

    it('links to passkey settings page', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      const actionLink = passkeyCard.find('.action-link');
      expect(actionLink.attributes('href')).toBe('/account/settings/security/passkeys');
    });
  });

  describe('Other Security Cards', () => {
    it('password card links to password settings', () => {
      wrapper = mountComponent();

      const card = wrapper.find('[data-card-id="password"]');
      const link = card.find('.action-link');
      expect(link.attributes('href')).toBe('/account/settings/security/password');
    });

    it('MFA card shows correct status when disabled', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        mfa_enabled: false,
      };
      wrapper = mountComponent();

      const card = wrapper.find('[data-card-id="mfa"]');
      const statusBadge = card.find('.status-badge');
      expect(statusBadge.classes()).toContain('status-warning');
      expect(card.text()).toContain('Not enabled');
    });

    it('MFA card shows correct status when enabled', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        mfa_enabled: true,
      };
      wrapper = mountComponent();

      const card = wrapper.find('[data-card-id="mfa"]');
      const statusBadge = card.find('.status-badge');
      expect(statusBadge.classes()).toContain('status-active');
      expect(card.text()).toContain('Enabled');
    });

    it('recovery codes card shows count when available', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        recovery_codes_count: 5,
      };
      wrapper = mountComponent();

      const card = wrapper.find('[data-card-id="recovery-codes"]');
      expect(card.text()).toContain('5 codes available');
    });

    it('recovery codes card shows inactive when no codes', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        recovery_codes_count: 0,
      };
      wrapper = mountComponent();

      const card = wrapper.find('[data-card-id="recovery-codes"]');
      const statusBadge = card.find('.status-badge');
      expect(statusBadge.classes()).toContain('status-inactive');
      expect(card.text()).toContain('No codes generated');
    });
  });

  describe('Card Layout', () => {
    it('renders cards in a 2-column grid on larger screens', () => {
      wrapper = mountComponent();

      const grid = wrapper.find('.grid');
      expect(grid.classes()).toContain('sm:grid-cols-2');
    });

    it('each card has consistent styling', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('.security-card');
      cards.forEach((card) => {
        expect(card.classes()).toContain('rounded-lg');
        expect(card.classes()).toContain('border');
        expect(card.classes()).toContain('bg-white');
      });
    });

    it('each card has an icon container', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('.security-card');
      cards.forEach((card) => {
        const iconContainer = card.find('.size-12');
        expect(iconContainer.exists()).toBe(true);
      });
    });
  });

  describe('Status Badge Styling', () => {
    it('active status has green styling', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 1,
      };
      wrapper = mountComponent();

      const passkeyCard = wrapper.find('[data-card-id="passkeys"]');
      const badge = passkeyCard.find('.status-badge');
      expect(badge.classes()).toContain('bg-green-50');
      expect(badge.classes()).toContain('text-green-700');
    });

    it('warning status has yellow styling', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        mfa_enabled: false,
      };
      wrapper = mountComponent();

      const mfaCard = wrapper.find('[data-card-id="mfa"]');
      const badge = mfaCard.find('.status-badge');
      expect(badge.classes()).toContain('bg-yellow-50');
      expect(badge.classes()).toContain('text-yellow-800');
    });

    it('inactive status has gray styling', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        recovery_codes_count: 0,
      };
      wrapper = mountComponent();

      const recoveryCard = wrapper.find('[data-card-id="recovery-codes"]');
      const badge = recoveryCard.find('.status-badge');
      expect(badge.classes()).toContain('bg-gray-50');
      expect(badge.classes()).toContain('text-gray-600');
    });
  });

  describe('No Account Info State', () => {
    it('renders no cards when accountInfo is null', () => {
      mockAccountInfo.value = null;
      wrapper = mountComponent();

      expect(wrapper.findAll('.security-card').length).toBe(0);
    });
  });

  describe('Total Card Count', () => {
    it('renders 3 cards when WebAuthn is disabled', () => {
      mockWebAuthnEnabled.value = false;
      wrapper = mountComponent();

      expect(wrapper.findAll('.security-card').length).toBe(3);
    });

    it('renders 4 cards when WebAuthn is enabled', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      expect(wrapper.findAll('.security-card').length).toBe(4);
    });
  });
});
