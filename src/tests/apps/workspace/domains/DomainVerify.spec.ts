// src/tests/apps/workspace/domains/DomainVerify.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import DomainVerify from '@/apps/workspace/domains/DomainVerify.vue';
import { ref, computed } from 'vue';

// Mock route params
const mockRouteParams = { extid: 'dm-test-extid' };

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: mockRouteParams,
  }),
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    back: vi.fn(),
  }),
}));

// Mock child components
vi.mock('@/apps/workspace/components/domains/DnsWidget.vue', () => ({
  default: {
    name: 'DnsWidget',
    template: '<div class="dns-widget" data-testid="dns-widget"><slot /></div>',
    props: ['domain', 'targetAddress', 'isApex', 'txtValidationHost', 'txtValidationValue', 'trd'],
    emits: ['records-verified'],
  },
}));

vi.mock('@/apps/workspace/components/domains/DomainVerificationInfo.vue', () => ({
  default: {
    name: 'DomainVerificationInfo',
    template: '<div class="domain-verification-info" data-testid="domain-verification-info" />',
    props: ['domain', 'mode'],
  },
}));

vi.mock('@/shared/components/ui/MoreInfoText.vue', () => ({
  default: {
    name: 'MoreInfoText',
    template: '<div class="more-info-text"><slot /></div>',
    props: ['textColor', 'bgColor'],
  },
}));

vi.mock('@/apps/workspace/components/domains/VerifyDomainDetails.vue', () => ({
  default: {
    name: 'VerifyDomainDetails',
    template: '<div class="verify-domain-details" data-testid="verify-domain-details" />',
    props: ['domain', 'cluster', 'withVerifyCTA'],
    emits: ['domain-verify'],
  },
}));

// Mock useDomain composable (used by DomainVerify for domain data)
const mockDomain = ref<any>(null);
const mockDetails = ref<any>(null);
const mockInitialize = vi.fn();
const mockUseDomainIsLoading = ref(false);

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: mockDomain,
    details: mockDetails,
    initialize: mockInitialize,
    isLoading: mockUseDomainIsLoading,
    isInitialized: ref(true),
    error: ref(null),
    canVerify: computed(() => true),
  }),
}));

// Mock useDomainsManager (used by DomainVerify for verifyDomain)
const mockVerifyDomain = vi.fn();
const mockIsLoading = ref(false);
const mockError = ref(null);

vi.mock('@/shared/composables/useDomainsManager', () => ({
  useDomainsManager: () => ({
    verifyDomain: mockVerifyDomain,
    isLoading: mockIsLoading,
    error: mockError,
  }),
}));

// Mock bootstrapStore with feature flags
const mockCust = ref({
  feature_flags: {
    dns_widget: true, // Enable DNS widget by default in tests
  },
});

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    cust: mockCust,
  }),
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: (store: { cust?: typeof mockCust }) => ({
      cust: store.cust ?? mockCust,
    }),
  };
});

// i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          verify_your_domain: 'Verify Your Domain',
          before_we_can_activate_links_for: 'Before we can activate links for',
          youll_need_to_complete_these_steps: "you'll need to complete these steps",
          configure_dns_records: 'Configure DNS Records',
          dns_widget_description: 'Use this widget to configure your DNS records',
          verify_domain: 'Verify Domain',
          loading_domain_information: 'Loading domain information...',
          domain_verification_initiated_successfully: 'Domain verification initiated successfully',
          in_order_to_connect_your_domain_youll_need_to_ha: 'In order to connect your domain, you\'ll need to have',
          if_you_already_have_a_cname_record_for_that_addr: 'If you already have a CNAME record for that address',
          and_remove_any_other_a_aaaa_or_cname_records_for: 'and remove any other A, AAAA, or CNAME records for',
          please_note_that_for_apex_domains: 'Please note that for apex domains',
          a_cname_record_is_not_allowed_instead_youll_need: 'a CNAME record is not allowed. Instead, you\'ll need',
        },
        COMMON: {
          processing: 'Processing...',
          important: 'Important',
        },
      },
    },
  },
});

// Test fixtures
const createMockDomain = (overrides = {}) => ({
  extid: 'dm-test-extid',
  display_domain: 'test.example.com',
  is_apex: false,
  vhost: { last_monitored_unix: 0 },
  txt_validation_host: '_challenge.test',
  txt_validation_value: 'verify123',
  trd: 'test',
  ...overrides,
});

const createMockCluster = (overrides = {}) => ({
  validation_strategy: 'approximated',
  proxy_host: 'proxy.example.com',
  proxy_ip: '192.168.1.1',
  proxy_name: 'Proxy Server',
  ...overrides,
});

describe('DomainVerify', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    vi.useFakeTimers();

    // Reset feature flags to enabled state for tests
    mockCust.value = { feature_flags: { dns_widget: true } };

    // Default mock data for useDomain
    mockDomain.value = createMockDomain();
    mockDetails.value = { cluster: createMockCluster() };
    mockInitialize.mockResolvedValue(undefined);
    mockVerifyDomain.mockResolvedValue({ success: true });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const mountComponent = async () => {
    const wrapper = mount(DomainVerify, {
      global: {
        plugins: [i18n, createPinia()],
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
        },
      },
    });
    await flushPromises();
    return wrapper;
  };

  describe('mount and auto-verification', () => {
    it('initializes domain data on mount', async () => {
      await mountComponent();

      expect(mockInitialize).toHaveBeenCalled();
    });

    it('auto-triggers verification on mount when showDnsWidget is true', async () => {
      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 0 } });
      mockDetails.value = { cluster: createMockCluster({ validation_strategy: 'approximated' }) };

      await mountComponent();

      expect(mockVerifyDomain).toHaveBeenCalledWith('dm-test-extid');
    });

    it('does NOT auto-trigger verification when domain is already verified', async () => {
      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 1704067200 } });
      mockDetails.value = { cluster: createMockCluster() };

      await mountComponent();

      expect(mockVerifyDomain).not.toHaveBeenCalled();
    });

    it('does NOT auto-trigger verification when validation_strategy is not approximated', async () => {
      mockDomain.value = createMockDomain();
      mockDetails.value = { cluster: createMockCluster({ validation_strategy: 'manual' }) };

      await mountComponent();

      expect(mockVerifyDomain).not.toHaveBeenCalled();
    });
  });

  describe('DNS widget event handling', () => {
    it('triggers backend verification when @records-verified fires', async () => {
      const wrapper = await mountComponent();
      vi.clearAllMocks(); // Clear auto-verification call

      // Advance time past cooldown to allow verification
      vi.advanceTimersByTime(11000);

      const dnsWidget = wrapper.findComponent({ name: 'DnsWidget' });
      await dnsWidget.vm.$emit('records-verified');
      await flushPromises();

      expect(mockVerifyDomain).toHaveBeenCalledWith('dm-test-extid');
    });

    it('refreshes domain data after successful widget verification', async () => {
      const wrapper = await mountComponent();
      vi.clearAllMocks();

      // Advance time past cooldown to allow verification
      vi.advanceTimersByTime(11000);

      const dnsWidget = wrapper.findComponent({ name: 'DnsWidget' });
      await dnsWidget.vm.$emit('records-verified');
      await flushPromises();

      // initialize called once after verification to refresh domain data
      expect(mockInitialize).toHaveBeenCalled();
    });
  });

  describe('manual verify button', () => {
    it('renders verify button when DNS widget is shown', async () => {
      const wrapper = await mountComponent();

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      expect(button.exists()).toBe(true);
      expect(button.text()).toContain('Verify Domain');
    });

    it('triggers verification on button click', async () => {
      const wrapper = await mountComponent();
      vi.clearAllMocks();

      // Advance time past cooldown
      vi.advanceTimersByTime(11000);

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      await button.trigger('click');
      await flushPromises();

      expect(mockVerifyDomain).toHaveBeenCalledWith('dm-test-extid');
    });

    it('button is disabled during verification', async () => {
      // Make verifyDomain hang to simulate in-progress state
      mockVerifyDomain.mockImplementation(() => new Promise(() => {}));

      const wrapper = await mountComponent();

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      expect(button.attributes('disabled')).toBeDefined();
    });

    it('button shows processing text during verification', async () => {
      mockVerifyDomain.mockImplementation(() => new Promise(() => {}));

      const wrapper = await mountComponent();

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      expect(button.text()).toContain('Processing...');
    });

    it('button re-enables after verification completes', async () => {
      mockVerifyDomain.mockResolvedValue({ success: true });

      const wrapper = await mountComponent();
      await flushPromises();

      // Advance time past cooldown
      vi.advanceTimersByTime(11000);

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      expect(button.attributes('disabled')).toBeUndefined();
    });
  });

  describe('rate limiting', () => {
    it('prevents rapid verification attempts within cooldown period', async () => {
      const wrapper = await mountComponent();
      vi.clearAllMocks();

      // First click (should be rate-limited since auto-verification just happened)
      const button = wrapper.find('[data-testid="verify-domain-button"]');
      await button.trigger('click');
      await flushPromises();

      expect(mockVerifyDomain).not.toHaveBeenCalled();
    });

    it('allows verification after cooldown period expires', async () => {
      const wrapper = await mountComponent();
      vi.clearAllMocks();

      // Advance time past the 10-second cooldown
      vi.advanceTimersByTime(11000);

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      await button.trigger('click');
      await flushPromises();

      expect(mockVerifyDomain).toHaveBeenCalledWith('dm-test-extid');
    });
  });

  // Note: Inline error handling tests removed - errors are now handled via
  // global notifications in useDomainsManager.wrap(), not inline BasicFormAlerts

  describe('conditional rendering', () => {
    it('shows DnsWidget when domain unverified + approximated strategy', async () => {
      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 0 } });
      mockDetails.value = { cluster: createMockCluster({ validation_strategy: 'approximated' }) };

      const wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="dns-widget"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="verify-domain-details"]').exists()).toBe(false);
    });

    it('shows VerifyDomainDetails when domain unverified + non-approximated', async () => {
      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 0 } });
      mockDetails.value = { cluster: createMockCluster({ validation_strategy: 'manual' }) };

      const wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="dns-widget"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="verify-domain-details"]').exists()).toBe(true);
    });

    it('shows DomainVerificationInfo when domain is verified', async () => {
      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 1704067200 } });
      mockDetails.value = { cluster: createMockCluster() };

      const wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="domain-verification-info"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="dns-widget"]').exists()).toBe(false);
    });

    it('shows loading message when domain is null', async () => {
      mockDomain.value = null;
      mockDetails.value = null;

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('Loading domain information...');
    });

    it('hides DnsWidget when dns_widget feature flag is disabled', async () => {
      // Disable the feature flag
      mockCust.value = { feature_flags: { dns_widget: false } };

      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 0 } });
      mockDetails.value = { cluster: createMockCluster({ validation_strategy: 'approximated' }) };

      const wrapper = await mountComponent();

      // Should show VerifyDomainDetails instead of DnsWidget
      expect(wrapper.find('[data-testid="dns-widget"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="verify-domain-details"]').exists()).toBe(true);
    });

    it('shows DnsWidget when dns_widget feature flag is enabled', async () => {
      // Enable the feature flag
      mockCust.value = { feature_flags: { dns_widget: true } };

      mockDomain.value = createMockDomain({ vhost: { last_monitored_unix: 0 } });
      mockDetails.value = { cluster: createMockCluster({ validation_strategy: 'approximated' }) };

      const wrapper = await mountComponent();

      expect(wrapper.find('[data-testid="dns-widget"]').exists()).toBe(true);
    });
  });

  describe('DNS target address computation', () => {
    it('returns proxy_ip for apex domains', async () => {
      mockDomain.value = createMockDomain({ is_apex: true });
      mockDetails.value = { cluster: createMockCluster({ proxy_ip: '10.0.0.1', proxy_host: 'proxy.test.com' }) };

      const wrapper = await mountComponent();

      const dnsWidget = wrapper.findComponent({ name: 'DnsWidget' });
      expect(dnsWidget.props('targetAddress')).toBe('10.0.0.1');
    });

    it('returns proxy_host for non-apex domains', async () => {
      mockDomain.value = createMockDomain({ is_apex: false });
      mockDetails.value = { cluster: createMockCluster({ proxy_ip: '10.0.0.1', proxy_host: 'proxy.test.com' }) };

      const wrapper = await mountComponent();

      const dnsWidget = wrapper.findComponent({ name: 'DnsWidget' });
      expect(dnsWidget.props('targetAddress')).toBe('proxy.test.com');
    });
  });

  describe('accessibility', () => {
    it('button has aria-busy attribute during verification', async () => {
      mockVerifyDomain.mockImplementation(() => new Promise(() => {}));

      const wrapper = await mountComponent();

      const button = wrapper.find('[data-testid="verify-domain-button"]');
      expect(button.attributes('aria-busy')).toBe('true');
    });

    // Note: error alerts aria-live test removed - inline errors replaced by global notifications
  });
});
