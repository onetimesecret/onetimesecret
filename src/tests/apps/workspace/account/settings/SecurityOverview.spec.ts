// src/tests/apps/workspace/account/settings/SecurityOverview.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import SecurityOverview from '@/apps/workspace/account/settings/SecurityOverview.vue';

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

  // Helper to find a security card by its icon name
  const findCardByIcon = (iconName: string) => {
    const cards = wrapper.findAll('.grid > div');
    return cards.find((card) => card.find(`[data-icon="${iconName}"]`).exists());
  };

  // Helper to find card by title text
  const findCardByTitle = (title: string) => {
    const cards = wrapper.findAll('.grid > div');
    return cards.find((card) => card.text().includes(title));
  };

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
    mount(SecurityOverview, {
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

      expect(findCardByIcon('lock-closed-solid')).toBeDefined();
      expect(findCardByIcon('key-solid')).toBeDefined();
      expect(findCardByIcon('document-text-solid')).toBeDefined();
    });
  });

  describe('Passkey Card (WebAuthn Feature Flag)', () => {
    it('shows passkey card when WebAuthn is enabled', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      expect(findCardByIcon('finger-print-solid')).toBeDefined();
    });

    it('hides passkey card when WebAuthn is disabled', () => {
      mockWebAuthnEnabled.value = false;
      wrapper = mountComponent();

      expect(findCardByIcon('finger-print-solid')).toBeUndefined();
    });

    it('displays passkey card title', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.text()).toContain('Passkeys');
    });

    it('displays passkey card description', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.text()).toContain('Use biometrics or security keys');
    });

    it('shows fingerprint icon on passkey card', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.find('[data-icon="finger-print-solid"]').exists()).toBe(true);
    });
  });

  describe('Passkey Count Display', () => {
    it('shows "Not configured" when no passkeys exist', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 0,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.text()).toContain('Not configured');
    });

    it('shows passkey count when passkeys exist (singular)', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 1,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.text()).toContain('1 passkey');
    });

    it('shows passkey count when multiple passkeys exist (plural)', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 3,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.text()).toContain('3 passkeys');
    });

    it('shows inactive status when no passkeys configured', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 0,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.text()).toContain('Not configured');
      expect(passkeyCard?.html()).toContain('bg-gray-50');
    });

    it('shows active status when passkeys configured', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 2,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.html()).toContain('bg-green-50');
    });
  });

  describe('Passkey Card Action', () => {
    it('shows "Enable" action when no passkeys exist', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 0,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      const actionLink = passkeyCard?.find('.router-link');
      expect(actionLink?.text()).toContain('Enable');
    });

    it('shows "Manage" action when passkeys exist', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        passkeys_count: 1,
      };
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      const actionLink = passkeyCard?.find('.router-link');
      expect(actionLink?.text()).toContain('Manage');
    });

    it('links to passkey settings page', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      const passkeyCard = findCardByIcon('finger-print-solid');
      const actionLink = passkeyCard?.find('.router-link');
      expect(actionLink?.attributes('href')).toBe('/account/settings/security/passkeys');
    });
  });

  describe('Other Security Cards', () => {
    it('password card links to password settings', () => {
      wrapper = mountComponent();

      const card = findCardByIcon('lock-closed-solid');
      const link = card?.find('.router-link');
      expect(link?.attributes('href')).toBe('/account/settings/security/password');
    });

    it('MFA card shows correct status when disabled', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        mfa_enabled: false,
      };
      wrapper = mountComponent();

      const card = findCardByIcon('key-solid');
      expect(card?.html()).toContain('bg-yellow-50');
      expect(card?.text()).toContain('Not enabled');
    });

    it('MFA card shows correct status when enabled', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        mfa_enabled: true,
      };
      wrapper = mountComponent();

      const card = findCardByIcon('key-solid');
      expect(card?.html()).toContain('bg-green-50');
      expect(card?.text()).toContain('Enabled');
    });

    it('recovery codes card shows count when available', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        recovery_codes_count: 5,
      };
      wrapper = mountComponent();

      const card = findCardByIcon('document-text-solid');
      expect(card?.text()).toContain('5 codes available');
    });

    it('recovery codes card shows inactive when no codes', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        recovery_codes_count: 0,
      };
      wrapper = mountComponent();

      const card = findCardByIcon('document-text-solid');
      expect(card?.html()).toContain('bg-gray-50');
      expect(card?.text()).toContain('No codes generated');
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

      const cards = wrapper.findAll('.grid > div');
      cards.forEach((card) => {
        expect(card.classes()).toContain('rounded-lg');
        expect(card.classes()).toContain('border');
        expect(card.classes()).toContain('bg-white');
      });
    });

    it('each card has an icon container', () => {
      wrapper = mountComponent();

      const cards = wrapper.findAll('.grid > div');
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

      const passkeyCard = findCardByIcon('finger-print-solid');
      expect(passkeyCard?.html()).toContain('bg-green-50');
      expect(passkeyCard?.html()).toContain('text-green-700');
    });

    it('warning status has yellow styling', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        mfa_enabled: false,
      };
      wrapper = mountComponent();

      const mfaCard = findCardByIcon('key-solid');
      expect(mfaCard?.html()).toContain('bg-yellow-50');
      expect(mfaCard?.html()).toContain('text-yellow-800');
    });

    it('inactive status has gray styling', () => {
      mockAccountInfo.value = {
        ...mockAccountInfo.value!,
        recovery_codes_count: 0,
      };
      wrapper = mountComponent();

      const recoveryCard = findCardByIcon('document-text-solid');
      expect(recoveryCard?.html()).toContain('bg-gray-50');
      expect(recoveryCard?.html()).toContain('text-gray-600');
    });
  });

  describe('No Account Info State', () => {
    it('renders no cards when accountInfo is null', () => {
      mockAccountInfo.value = null;
      wrapper = mountComponent();

      expect(wrapper.findAll('.grid > div').length).toBe(0);
    });
  });

  describe('Total Card Count', () => {
    it('renders 3 cards when WebAuthn is disabled', () => {
      mockWebAuthnEnabled.value = false;
      wrapper = mountComponent();

      expect(wrapper.findAll('.grid > div').length).toBe(3);
    });

    it('renders 4 cards when WebAuthn is enabled', () => {
      mockWebAuthnEnabled.value = true;
      wrapper = mountComponent();

      expect(wrapper.findAll('.grid > div').length).toBe(4);
    });
  });
});
