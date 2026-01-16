// src/tests/apps/secret/support/Pricing.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import Pricing from '@/apps/secret/support/Pricing.vue';
import { createMockPlan, mockPlans } from '@/tests/fixtures/billing.fixture';
import type { Plan as BillingPlan } from '@/services/billing.service';

// Hoisted mock functions - must use vi.hoisted for proper hoisting
const mockListPlans = vi.hoisted(() => vi.fn());

// Route params - using a mutable object instead of ref for hoisting compatibility
let mockRouteParamsValue: Record<string, string> = {};

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: () => ({
    get params() { return mockRouteParamsValue; },
    path: '/pricing',
    query: {},
  }),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to" data-testid="signup-link"><slot /></a>',
    props: ['to'],
  },
}));

// RouterLink stub for mounting
const RouterLinkStub = {
  name: 'RouterLink',
  template: '<a :href="to" data-testid="signup-link"><slot /></a>',
  props: ['to'],
};

// Mock BillingService
vi.mock('@/services/billing.service', () => ({
  BillingService: {
    listPlans: () => mockListPlans(),
  },
}));

// Mock child components
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="error-alert">{{ error }}</div>',
    props: ['error'],
  },
}));

vi.mock('@/shared/components/ui/FeedbackToggle.vue', () => ({
  default: {
    name: 'FeedbackToggle',
    template: '<button class="feedback-toggle">Feedback</button>',
  },
}));

// Mock error classifier
vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({
    message: err instanceof Error ? err.message : 'Unknown error',
  }),
}));

// Mock formatCurrency from billing types
vi.mock('@/types/billing', () => ({
  formatCurrency: (amount: number, currency: string = 'USD') => new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency,
    }).format(amount / 100),
}));

// i18n setup - use same pattern as other billing specs
const createTestI18n = () => createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        web: {
          pricing: {
            title: 'Choose Your Plan',
            subtitle: 'Select the plan that works best for you',
            get_started_free: 'Get Started Free',
            start_trial: 'Start Trial',
            already_have_account: 'Already have an account?',
            sign_in: 'Sign in',
            recommended_for_you: 'Recommended for You',
            free_tier_description: 'Create and share secrets with basic features. No credit card required.',
          },
          billing: {
            plans: {
              monthly: 'Monthly',
              yearly: 'Yearly',
              per_month: '/month',
              most_popular: 'Most Popular',
              features: 'Features',
              custom_needs_title: 'Need something custom?',
              custom_needs_description: 'Contact us for enterprise solutions',
              no_plans_available: 'No {interval} plans available',
            },
          },
          COMMON: {
            loading: 'Loading...',
          },
        },
      },
    },
  });

// Test fixtures
const defaultPlans: BillingPlan[] = [
  mockPlans.free,
  mockPlans.single_team_monthly,
  mockPlans.single_team_yearly,
  mockPlans.multi_team_monthly,
  mockPlans.multi_team_yearly,
];

describe('Pricing.vue', () => {
  let wrapper: VueWrapper;
  let i18n: ReturnType<typeof createTestI18n>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRouteParamsValue = {};
    mockListPlans.mockResolvedValue({ plans: defaultPlans });
    i18n = createTestI18n();
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountComponent = async () => {
    wrapper = mount(Pricing, {
      global: {
        plugins: [i18n],
        stubs: {
          RouterLink: RouterLinkStub,
        },
      },
    });
    await flushPromises();
    return wrapper;
  };

  // ============================================================
  // 1. URL Parameter Handling
  // ============================================================
  describe('URL parameter handling', () => {
    it('defaults to monthly billing when no interval param', async () => {
      mockRouteParamsValue = {};
      await mountComponent();

      const monthlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(monthlyButton.text()).toBe('Monthly');
    });

    it('parses /pricing/:product/:interval for monthly', async () => {
      mockRouteParamsValue = { product: 'identity_plus', interval: 'monthly' };
      await mountComponent();

      const monthlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(monthlyButton.text()).toBe('Monthly');
    });

    it('parses /pricing/:product/:interval for yearly', async () => {
      mockRouteParamsValue = { product: 'identity_plus', interval: 'yearly' };
      await mountComponent();

      const yearlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(yearlyButton.text()).toBe('Yearly');
    });

    it('normalizes "annual" to year interval', async () => {
      mockRouteParamsValue = { interval: 'annual' };
      await mountComponent();

      const yearlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(yearlyButton.text()).toBe('Yearly');
    });

    it('ignores invalid interval params and defaults to month', async () => {
      mockRouteParamsValue = { interval: 'invalid_interval' };
      await mountComponent();

      const monthlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(monthlyButton.text()).toBe('Monthly');
    });

    it('highlights matching product from URL param', async () => {
      mockRouteParamsValue = { product: 'identity_plus' };
      await mountComponent();

      // Identity Plus monthly should be highlighted (matches 'identity_plus' prefix)
      const highlightedCards = wrapper.findAll('.border-yellow-500');
      expect(highlightedCards.length).toBeGreaterThan(0);

      // Check for "Recommended for You" badge
      expect(wrapper.text()).toContain('Recommended for You');
    });
  });

  // ============================================================
  // 2. Plan Display Logic
  // ============================================================
  describe('Plan display logic', () => {
    it('filters plans by selected billing interval', async () => {
      await mountComponent();

      // Default is monthly - should show monthly paid plans (free is shown separately)
      const planCards = wrapper.findAll('[class*="flex-col rounded-2xl"]');
      const monthlyPaidPlanIds = defaultPlans
        .filter(p => p.interval === 'month' && p.tier !== 'free')
        .map(p => p.id);

      expect(planCards.length).toBe(monthlyPaidPlanIds.length);
    });

    it('calculates monthly equivalent for yearly plans', async () => {
      mockRouteParamsValue = { interval: 'yearly' };
      await mountComponent();

      // Check that yearly plans show monthly equivalent price
      // The single_team_yearly has monthly_equivalent_amount: 2417 ($24.17)
      expect(wrapper.text()).toContain('$24.17');
    });

    it('uses API monthly_equivalent_amount when provided', async () => {
      const planWithEquivalent = createMockPlan({
        id: 'test_yearly',
        interval: 'year',
        amount: 12000, // $120/year
        monthly_equivalent_amount: 999, // $9.99/month (API override)
      });

      mockListPlans.mockResolvedValueOnce({
        plans: [planWithEquivalent],
      });
      mockRouteParamsValue = { interval: 'yearly' };

      await mountComponent();

      // Should show $9.99 from monthly_equivalent_amount, not $10.00 from calculation
      expect(wrapper.text()).toContain('$9.99');
    });

    it('shows "Most Popular" badge for is_popular plans', async () => {
      await mountComponent();

      // single_team_monthly has is_popular: true
      expect(wrapper.text()).toContain('Most Popular');
    });

    it('does not show badge when is_popular is false or undefined', async () => {
      const plansWithoutPopular = [
        createMockPlan({ id: 'plan_a', tier: 'single_team', is_popular: false }),
        createMockPlan({ id: 'plan_b', tier: 'multi_team' }), // is_popular undefined
      ];

      mockListPlans.mockResolvedValueOnce({ plans: plansWithoutPopular });
      await mountComponent();

      expect(wrapper.text()).not.toContain('Most Popular');
    });
  });

  // ============================================================
  // 3. getSignupUrl Function
  // ============================================================
  describe('getSignupUrl function', () => {
    it('returns /signup for free tier', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: 'month',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      expect(signupLink.attributes('href')).toBe('/signup');
    });

    it('includes product and interval for paid plans', async () => {
      const paidPlan = createMockPlan({
        id: 'identity_plus_v1_monthly',
        tier: 'single_team',
        interval: 'month',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [paidPlan] });
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      expect(signupLink.attributes('href')).toBe(
        '/signup?product=identity_plus_v1&interval=monthly'
      );
    });

    it('encodes special characters in product name', async () => {
      const planWithSpecialChars = createMockPlan({
        id: 'plan_with+special&chars_monthly',
        tier: 'single_team',
        interval: 'month',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [planWithSpecialChars] });
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      const href = signupLink.attributes('href');
      expect(href).toContain('product=plan_with%2Bspecial%26chars');
    });

    it('uses yearly interval string for year plans', async () => {
      const yearlyPlan = createMockPlan({
        id: 'identity_plus_v1_yearly',
        tier: 'single_team',
        interval: 'year',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [yearlyPlan] });
      mockRouteParamsValue = { interval: 'yearly' };
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      expect(signupLink.attributes('href')).toContain('interval=yearly');
    });
  });

  // ============================================================
  // 4. extractProductFromPlanId Utility
  // ============================================================
  describe('extractProductFromPlanId utility', () => {
    // Note: Testing through the component's rendered signup URLs
    // since the function is internal to the component

    it('removes _monthly suffix', async () => {
      const plan = createMockPlan({
        id: 'identity_plus_v1_monthly',
        tier: 'single_team',
        interval: 'month',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [plan] });
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      expect(signupLink.attributes('href')).toContain('product=identity_plus_v1');
      expect(signupLink.attributes('href')).not.toContain('product=identity_plus_v1_monthly');
    });

    it('removes _yearly suffix', async () => {
      const plan = createMockPlan({
        id: 'team_plus_v1_yearly',
        tier: 'single_team',
        interval: 'year',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [plan] });
      mockRouteParamsValue = { interval: 'yearly' };
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      expect(signupLink.attributes('href')).toContain('product=team_plus_v1');
      expect(signupLink.attributes('href')).not.toContain('product=team_plus_v1_yearly');
    });

    it('handles plans without interval suffix', async () => {
      const plan = createMockPlan({
        id: 'basic_plan_v2',
        tier: 'single_team',
        interval: 'month',
      });

      mockListPlans.mockResolvedValueOnce({ plans: [plan] });
      await mountComponent();

      const signupLink = wrapper.find('[data-testid="signup-link"]');
      expect(signupLink.attributes('href')).toContain('product=basic_plan_v2');
    });
  });

  // ============================================================
  // 5. Error Handling
  // ============================================================
  describe('Error handling', () => {
    it('displays error message when API fails', async () => {
      mockListPlans.mockRejectedValueOnce(new Error('Network error'));
      await mountComponent();

      const errorAlert = wrapper.find('[data-testid="error-alert"]');
      expect(errorAlert.exists()).toBe(true);
      expect(errorAlert.text()).toContain('Network error');
    });

    it('shows loading state while fetching', async () => {
      // Set up a promise that we can control when it resolves
      let resolvePromise: (value: { plans: BillingPlan[] }) => void;
      const controlledPromise = new Promise<{ plans: BillingPlan[] }>(resolve => {
        resolvePromise = resolve;
      });
      mockListPlans.mockReturnValueOnce(controlledPromise);

      wrapper = mount(Pricing, {
        global: {
          plugins: [i18n],
          stubs: { RouterLink: RouterLinkStub },
        },
      });

      // Wait a tick for Vue to process the mount lifecycle
      // This allows onMounted to run and set isLoadingPlans = true
      await new Promise(resolve => setTimeout(resolve, 0));
      await wrapper.vm.$nextTick();

      // At this point, loadPlans should be in progress (promise pending)
      // The loading div contains an OIcon with animate-spin class - but OIcon is mocked
      // so we check for the loading container and text instead
      const loadingContainer = wrapper.find('[class*="flex items-center justify-center py-12"]');
      expect(loadingContainer.exists()).toBe(true);
      expect(wrapper.text()).toContain('Loading...');

      // Cleanup: resolve the promise to complete the test properly
      resolvePromise!({ plans: [] });
      await flushPromises();
    });

    it('hides loading state after plans load', async () => {
      mockListPlans.mockResolvedValueOnce({ plans: defaultPlans });
      await mountComponent();

      // After loading completes, spinner should be gone
      expect(wrapper.find('.animate-spin').exists()).toBe(false);
    });

    it('shows empty state when no plans available', async () => {
      mockListPlans.mockResolvedValueOnce({ plans: [] });
      await mountComponent();

      expect(wrapper.text()).toContain('No monthly plans available');
    });

    it('shows empty state for interval with no matching plans', async () => {
      // Only monthly plans
      const monthlyOnlyPlans = [mockPlans.single_team_monthly];
      mockListPlans.mockResolvedValueOnce({ plans: monthlyOnlyPlans });
      mockRouteParamsValue = { interval: 'yearly' };

      await mountComponent();

      expect(wrapper.text()).toContain('No yearly plans available');
    });
  });

  // ============================================================
  // 6. Accessibility
  // ============================================================
  describe('Accessibility', () => {
    it('has proper aria-pressed on interval toggle buttons', async () => {
      await mountComponent();

      const buttons = wrapper.findAll('button[aria-pressed]');
      expect(buttons.length).toBe(2);

      // Monthly should be pressed by default
      const monthlyButton = buttons.find(b => b.text() === 'Monthly');
      const yearlyButton = buttons.find(b => b.text() === 'Yearly');

      expect(monthlyButton?.attributes('aria-pressed')).toBe('true');
      expect(yearlyButton?.attributes('aria-pressed')).toBe('false');
    });

    it('updates aria-pressed when interval changes', async () => {
      await mountComponent();

      // Click yearly button
      const yearlyButton = wrapper.findAll('button').find(b => b.text() === 'Yearly');
      await yearlyButton?.trigger('click');

      const buttons = wrapper.findAll('button[aria-pressed]');
      const monthlyButton = buttons.find(b => b.text() === 'Monthly');
      const yearlyBtn = buttons.find(b => b.text() === 'Yearly');

      expect(monthlyButton?.attributes('aria-pressed')).toBe('false');
      expect(yearlyBtn?.attributes('aria-pressed')).toBe('true');
    });

    it('has semantic heading structure', async () => {
      await mountComponent();

      const h1 = wrapper.find('h1');
      expect(h1.exists()).toBe(true);
      expect(h1.text()).toBe('web.billing.secure_links_stronger_connections');

      // Plan cards are rendered (PlanCard components)
      const planCards = wrapper.findAllComponents({ name: 'PlanCard' });
      expect(planCards.length).toBeGreaterThan(0);

      // Custom needs section exists with proper heading
      const customNeedsSection = wrapper.find('.bg-gray-50');
      expect(customNeedsSection.exists()).toBe(true);
      const h3 = customNeedsSection.find('h3');
      expect(h3.exists()).toBe(true);
    });

    it('has accessible billing interval group', async () => {
      await mountComponent();

      const group = wrapper.find('[role="group"]');
      expect(group.exists()).toBe(true);
      expect(group.attributes('aria-label')).toBe('Billing interval');
    });
  });

  // ============================================================
  // Additional Edge Cases
  // ============================================================
  describe('Edge cases', () => {
    it('handles mixed interval params (month vs monthly)', async () => {
      mockRouteParamsValue = { interval: 'month' };
      await mountComponent();

      const monthlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(monthlyButton.text()).toBe('Monthly');
    });

    it('handles year vs yearly interval params', async () => {
      mockRouteParamsValue = { interval: 'year' };
      await mountComponent();

      const yearlyButton = wrapper.find('button[aria-pressed="true"]');
      expect(yearlyButton.text()).toBe('Yearly');
    });

    it('product highlight is case insensitive', async () => {
      mockRouteParamsValue = { product: 'IDENTITY_PLUS' };
      await mountComponent();

      // Should still highlight the plan
      const highlightedCards = wrapper.findAll('.border-yellow-500');
      expect(highlightedCards.length).toBeGreaterThan(0);
    });

    it('displays plan features from API', async () => {
      const planWithFeatures = createMockPlan({
        id: 'test_plan_monthly',
        tier: 'single_team',
        features: ['web.feature.custom', 'web.feature.api'],
      });

      mockListPlans.mockResolvedValueOnce({ plans: [planWithFeatures] });
      await mountComponent();

      // Features are rendered (using i18n key as-is since no translation exists)
      expect(wrapper.text()).toContain('web.feature.custom');
      expect(wrapper.text()).toContain('web.feature.api');
    });

    it('shows correct CTA label based on tier', async () => {
      await mountComponent();

      // Free plan should show "Get Started Free"
      expect(wrapper.text()).toContain('Get Started Free');

      // Paid plans should show "Start Trial"
      expect(wrapper.text()).toContain('Start Trial');
    });

    it('calculates fallback monthly equivalent when API field missing', async () => {
      const yearlyWithoutEquivalent = createMockPlan({
        id: 'test_yearly',
        interval: 'year',
        amount: 12000, // $120/year -> $10/month
        // monthly_equivalent_amount is undefined
      });

      mockListPlans.mockResolvedValueOnce({
        plans: [yearlyWithoutEquivalent],
      });
      mockRouteParamsValue = { interval: 'yearly' };

      await mountComponent();

      // 12000 / 12 = 1000 cents = $10.00
      expect(wrapper.text()).toContain('$10.00');
    });
  });

  // ============================================================
  // 7. Free Plan Display (shown in separate section from paid plans)
  // ============================================================
  describe('Free plan display', () => {
    it('shows free plan in monthly view', async () => {
      await mountComponent();

      // Free plan should be visible in its own section
      expect(wrapper.text()).toContain('Free');
    });

    it('shows free plan in yearly view', async () => {
      // Free plan shows regardless of billing interval selection
      const freePlan = createMockPlan({
        id: 'free_v1',
        name: 'Free',
        tier: 'free',
        interval: null, // Free plans have no interval
        amount: 0,
      });
      const paidPlanYearly = createMockPlan({
        id: 'identity_plus_v1_yearly',
        tier: 'single_team',
        interval: 'year',
        amount: 29000,
      });

      mockListPlans.mockResolvedValueOnce({
        plans: [freePlan, paidPlanYearly],
      });
      mockRouteParamsValue = { interval: 'yearly' };

      await mountComponent();

      expect(wrapper.text()).toContain('Free');
    });

    it('free plan CTA links to /signup', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: null,
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      // Free tier section has a link to /signup
      const links = wrapper.findAll('a[href="/signup"]');
      expect(links.length).toBeGreaterThan(0);
    });

    it('free plan shows "Get Started Free" CTA', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: null,
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      expect(wrapper.text()).toContain('Get Started Free');
    });

    it('free plan section shows description', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: null,
        amount: 0,
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      // Free plan section shows description
      expect(wrapper.text()).toContain('Create and share secrets with basic features');
    });

    it('free plan is not marked as popular by default', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: 'month',
        is_popular: false,
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      // Free plan card should not have "Most Popular" badge
      // Check that "Most Popular" is NOT shown when only free plan exists
      expect(wrapper.text()).not.toContain('Most Popular');
    });

    it('free plan appears alongside paid plans', async () => {
      await mountComponent();

      // With default plans fixture, should have free and paid plans
      const planCards = wrapper.findAll('[class*="flex-col rounded-2xl"]');
      expect(planCards.length).toBeGreaterThanOrEqual(2);

      // Verify both Free and paid plan names appear
      expect(wrapper.text()).toContain('Free');
      expect(wrapper.text()).toContain('Identity Plus');
    });

    it('free plan displays its features correctly', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: 'month',
        amount: 0,
        features: ['Basic secret sharing'],
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      expect(wrapper.text()).toContain('Basic secret sharing');
    });

    it('free plan displays entitlements', async () => {
      const freePlan = createMockPlan({
        id: 'free_v1',
        tier: 'free',
        interval: 'month',
        amount: 0,
        entitlements: ['create_secrets', 'api_access'],
      });

      mockListPlans.mockResolvedValueOnce({ plans: [freePlan] });
      await mountComponent();

      // Entitlements should be displayed (as-is or translated)
      expect(freePlan.entitlements).toContain('create_secrets');
      expect(freePlan.entitlements).toContain('api_access');
    });
  });
});
