// src/tests/apps/workspace/domains/DomainSignup.spec.ts
//
// Focused tests for DomainSignup.vue's loading/entitlement skeleton guard.
//
// DomainSignup is a structural copy of DomainSso: useSignupConfig inits
// isLoading = ref(true) and onMounted skips initializeSignupConfig() for
// unentitled users. The full-page skeleton guard must therefore be qualified by
// the entitlement, or it spins forever for unentitled users instead of showing
// the upgrade prompt. The regression test below locks that invariant in.

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import { ref } from 'vue';
import DomainSignup from '@/apps/workspace/domains/DomainSignup.vue';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

const mockRouterPush = vi.fn();

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockRouterPush,
  }),
  onBeforeRouteLeave: vi.fn(),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="form-alerts" :data-error="error">{{ error }}</div>',
    props: ['error', 'success'],
  },
}));

vi.mock('@/apps/workspace/components/domains/DomainSignupConfigForm.vue', () => ({
  default: {
    name: 'DomainSignupConfigForm',
    template: '<div class="domain-signup-config-form" data-testid="domain-signup-config-form" :data-domain-ext-id="domainExtId" />',
    props: ['domainExtId'],
    // `can-save` drives the header's Save button (the form owns validity and
    // relays it up). Emit true on mount so the seam test can click an enabled
    // header Save without reproducing the real form's validation.
    emits: ['save', 'delete', 'discard', 'can-save'],
    mounted() {
      this.$emit('can-save', true);
    },
  },
}));

// Domain composable mock
const mockDomain = ref<{ display_domain: string } | null>(null);
const mockDomainLoading = ref(false);
const mockDomainError = ref<{ message: string } | null>(null);
const mockInitializeDomain = vi.fn();

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: mockDomain,
    isLoading: mockDomainLoading,
    error: mockDomainError,
    initialize: mockInitializeDomain,
  }),
}));

// Signup config composable mock. isLoading mirrors the real composable's
// ref(true) init; tests that simulate the unentitled "fetch skipped" state set
// it true explicitly (the real initialize() never runs to flip it false).
const mockSignupLoading = ref(false);
const mockSignupInitialized = ref(true);
const mockSignupSaving = ref(false);
const mockSignupDeleting = ref(false);
const mockSignupError = ref<{ message: string } | null>(null);
const mockSignupConfig = ref(null);
const mockFormState = ref({ enabled: false });
const mockIsConfigured = ref(false);
const mockHasUnsavedChanges = ref(false);
const mockInitializeSignupConfig = vi.fn();
const mockSaveConfig = vi.fn();
const mockDeleteConfig = vi.fn();
const mockDiscardChanges = vi.fn();

vi.mock('@/shared/composables/useSignupConfig', () => ({
  useSignupConfig: () => ({
    isLoading: mockSignupLoading,
    isInitialized: mockSignupInitialized,
    isSaving: mockSignupSaving,
    isDeleting: mockSignupDeleting,
    error: mockSignupError,
    signupConfig: mockSignupConfig,
    formState: mockFormState,
    isConfigured: mockIsConfigured,
    hasUnsavedChanges: mockHasUnsavedChanges,
    initialize: mockInitializeSignupConfig,
    saveConfig: mockSaveConfig,
    deleteConfig: mockDeleteConfig,
    discardChanges: mockDiscardChanges,
  }),
}));

// Entitlements mock
const mockCanCustomSignup = ref(true);

vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    can: (entitlement: string) =>
      entitlement === 'custom_signup_validation' ? mockCanCustomSignup.value : false,
  }),
}));

// Store mocks. storeToRefs is mocked to ignore its argument and return a merged
// object, so the same stub serves both the organizationStore and bootstrapStore
// destructures in the component.
const mockOrganizations = ref([
  { extid: 'org_123', display_name: 'Test Org', entitlements: ['custom_signup_validation'] },
]);
const mockAuthentication = ref<{ enabled: boolean; signup: boolean } | null>(null);

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    organizations: mockOrganizations.value,
  }),
}));

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    authentication: mockAuthentication.value,
  }),
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: () => ({
      organizations: mockOrganizations,
      authentication: mockAuthentication,
    }),
  };
});

vi.mock('@/types/organization', () => ({
  ENTITLEMENTS: {
    CUSTOM_SIGNUP_VALIDATION: 'custom_signup_validation',
  },
}));

// i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          signup: {
            title: 'Domain Signup Configuration',
            access_denied: 'Access Denied',
            upgrade_to_configure: 'You do not have permission to configure signup validation for this domain. Upgrade your plan to enable this feature.',
            config_description: 'Configure signup validation for this domain.',
            not_configured_notice: 'Signup validation is not configured for this domain yet.',
            site_signups_disabled_warning: 'Signups are disabled site-wide; this policy is currently dormant.',
          },
        },
        billing: {
          overview: {
            view_plans_action: 'View Plans',
          },
        },
        branding: {
          you_have_unsaved_changes_are_you_sure: 'You have unsaved changes. Are you sure you want to leave?',
        },
        COMMON: {
          back: 'Back',
          loading: 'Loading...',
        },
        LABELS: {
          update: 'Update',
          updating: 'Updating...',
        },
      },
    },
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('DomainSignup', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    mockDomain.value = null;
    mockDomainLoading.value = false;
    mockDomainError.value = null;

    mockSignupLoading.value = false;
    mockSignupInitialized.value = true;
    mockSignupSaving.value = false;
    mockSignupDeleting.value = false;
    mockSignupError.value = null;
    mockSignupConfig.value = null;
    mockFormState.value = { enabled: false };
    mockIsConfigured.value = false;
    mockHasUnsavedChanges.value = false;

    mockCanCustomSignup.value = true;
    mockAuthentication.value = null;
    mockOrganizations.value = [
      { extid: 'org_123', display_name: 'Test Org', entitlements: ['custom_signup_validation'] },
    ];
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (props = {}) => {
    const component = mount(DomainSignup, {
      props: {
        orgid: 'org_123',
        extid: 'dm_test123',
        ...props,
      },
      global: {
        plugins: [i18n, createPinia()],
        stubs: {
          Teleport: true,
        },
      },
    });
    await flushPromises();
    return component;
  };

  // ───────────────────────────────────────────────────────────────────────────
  // Loading / entitlement skeleton guard
  // ───────────────────────────────────────────────────────────────────────────

  describe('Loading / entitlement skeleton guard', () => {
    it('shows the loading skeleton while the domain is loading', async () => {
      mockDomainLoading.value = true;
      wrapper = await mountComponent();

      const skeleton = wrapper.find('[aria-busy="true"]');
      expect(skeleton.exists()).toBe(true);
    });

    // Regression for the latent skeleton-guard trap. Unentitled users skip
    // initializeSignupConfig() in onMounted, so the composable's isLoading stays
    // at its ref(true) init. The skeleton guard must be qualified by the
    // entitlement — domainLoading || (canCustomSignup && signupLoading). The
    // naive domainLoading || signupLoading form spins the skeleton forever and
    // the upgrade prompt never renders. Mirrors the shipped DomainSignin fix.
    it('shows the access-denied guard, not a perpetual skeleton, when unentitled with the config fetch skipped', async () => {
      mockCanCustomSignup.value = false;
      mockSignupLoading.value = true; // initialize() skipped -> isLoading stuck at ref(true)
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      // Skeleton must not win the v-if (aria-busy is skeleton-unique here)...
      expect(wrapper.find('[aria-busy="true"]').exists()).toBe(false);
      // ...the access-denied upgrade guard renders instead.
      expect(wrapper.text()).toContain('Access Denied');
      expect(wrapper.find('[data-testid="domain-signup-config-form"]').exists()).toBe(false);
    });

    it('renders the config form when entitled and the domain has loaded', async () => {
      mockCanCustomSignup.value = true;
      mockSignupLoading.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      expect(wrapper.find('[aria-busy="true"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="domain-signup-config-form"]').exists()).toBe(true);
    });

    // Positive half of the guard invariant: an entitled user mid config-fetch
    // must see the skeleton. Pins the (canCustomSignup && signupLoading) clause
    // so a future "simplify to domainLoading" edit goes red instead of silently
    // dropping the skeleton during a real fetch.
    it('shows the skeleton while the config fetches for an entitled user', async () => {
      mockCanCustomSignup.value = true;
      mockSignupLoading.value = true;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      expect(wrapper.find('[aria-busy="true"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-signup-config-form"]').exists()).toBe(false);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Header Save wiring (the page ↔ DomainHeader seam)
  //
  // The primary Save ("Update") moved from the config form into the shared
  // DomainHeader. The form owns validity and relays it via `can-save`; the page
  // holds `formCanSave` and drives the header's save-visible/save-disabled/@save.
  // These exercise that seam end-to-end (real DomainHeader, stubbed form).
  // ───────────────────────────────────────────────────────────────────────────

  describe('Header Save', () => {
    // DomainHeader's Save button carries the content-save icon; Back carries
    // arrow-left. OIcon is stubbed to expose `data-icon-name`, so this is
    // unambiguous.
    const findHeaderSave = (w: VueWrapper) =>
      w.findAll('button').find((b) => b.find('[data-icon-name="content-save"]').exists());

    it('renders an enabled header Save and routes clicks to saveConfig when entitled', async () => {
      mockCanCustomSignup.value = true;
      mockSignupInitialized.value = true;
      mockSignupLoading.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const saveBtn = findHeaderSave(wrapper);
      // save-visible = canCustomSignup && isInitialized; the stub form's
      // mounted can-save=true drives save-disabled off.
      expect(saveBtn?.exists()).toBe(true);
      expect(saveBtn!.attributes('disabled')).toBeUndefined();

      await saveBtn!.trigger('click');
      expect(mockSaveConfig).toHaveBeenCalledTimes(1);
    });

    it('hides the header Save when unentitled', async () => {
      mockCanCustomSignup.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      expect(findHeaderSave(wrapper)).toBeUndefined();
    });
  });
});
