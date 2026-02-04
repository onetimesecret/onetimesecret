// src/tests/fixtures/billing.fixture.ts

import type {
  BillingOverviewResponse,
  Plan,
  PlanChangePreviewResponse,
  SubscriptionStatusResponse,
} from '@/services/billing.service';
import type { ExtId, ObjId } from '@/types/identifiers';
import type { Organization } from '@/types/organization';

/**
 * Plan tier type for billing fixtures
 */
export type PlanTier = 'free' | 'single_team' | 'multi_team';

/**
 * Factory function to create mock billing plans
 */
export function createMockPlan(overrides: Partial<Plan> = {}): Plan {
  return {
    id: 'plan_test_123',
    stripe_price_id: 'price_test_123',
    name: 'Test Plan',
    tier: 'single_team',
    interval: 'month',
    amount: 1499,
    currency: 'usd',
    region: 'US',
    display_order: 100,
    features: ['Feature 1', 'Feature 2'],
    limits: { teams: 1, members_per_team: 10 },
    entitlements: ['create_secrets', 'api_access', 'custom_domains'],
    ...overrides,
  };
}

/**
 * Pre-configured mock plans for common test scenarios
 */
export const mockPlans: Record<string, Plan> = {
  free: createMockPlan({
    id: 'free_v1',
    stripe_price_id: null, // Free plans have no Stripe price
    name: 'Free',
    tier: 'free',
    interval: null, // Free plans have no interval
    amount: 0,
    display_order: 0,
    features: ['Basic secret sharing'],
    limits: { teams: 0, members_per_team: 0 },
    entitlements: [],
  }),
  /**
   * Legacy "identity" plan - grandfathered Early Supporter plan.
   * This plan is NOT available for new subscriptions but is honored for existing customers.
   * Maps to single_team tier for feature parity with Identity Plus.
   */
  legacy_identity: createMockPlan({
    id: 'identity',
    stripe_price_id: null, // Legacy plans may not have Stripe price IDs
    name: 'Identity Plus (Early Supporter)',
    tier: 'single_team', // Same tier as identity_plus for feature parity
    interval: 'month', // Assumed monthly billing
    amount: 1900, // Original early supporter price
    display_order: -1, // Not shown in plan selector (legacy)
    plan_code: 'identity',
    features: ['Custom domains', 'API access', 'Branding', 'Early Supporter perks'],
    limits: { teams: 1, members_per_team: 10 },
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
  }),
  single_team_monthly: createMockPlan({
    id: 'identity_plus_v1_monthly',
    stripe_price_id: 'price_single_monthly',
    name: 'Identity Plus',
    tier: 'single_team',
    interval: 'month',
    amount: 2900,
    display_order: 10,
    plan_code: 'identity_plus_v1',
    is_popular: true,
    features: ['Custom domains', 'API access', 'Branding'],
    limits: { teams: 1, members_per_team: 10 },
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
  }),
  single_team_yearly: createMockPlan({
    id: 'identity_plus_v1_yearly',
    stripe_price_id: 'price_single_yearly',
    name: 'Identity Plus',
    tier: 'single_team',
    interval: 'year',
    amount: 29000,
    display_order: 11,
    plan_code: 'identity_plus_v1',
    monthly_equivalent_amount: 2417,
    features: ['Custom domains', 'API access', 'Branding'],
    limits: { teams: 1, members_per_team: 10 },
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
  }),
  multi_team_monthly: createMockPlan({
    id: 'team_plus_v1_monthly',
    stripe_price_id: 'price_multi_monthly',
    name: 'Team Plus',
    tier: 'multi_team',
    interval: 'month',
    amount: 9900,
    display_order: 20,
    plan_code: 'team_plus_v1',
    features: ['All Identity Plus features', 'Multiple teams', 'SSO', 'Audit logs'],
    limits: { teams: 5, members_per_team: 25 },
    entitlements: [
      'api_access',
      'custom_domains',
      'custom_branding',
      'manage_teams',
      'manage_members',
      'audit_logs',
    ],
  }),
  multi_team_yearly: createMockPlan({
    id: 'team_plus_v1_yearly',
    stripe_price_id: 'price_multi_yearly',
    name: 'Team Plus',
    tier: 'multi_team',
    interval: 'year',
    amount: 99000,
    display_order: 21,
    plan_code: 'team_plus_v1',
    monthly_equivalent_amount: 8250,
    features: ['All Identity Plus features', 'Multiple teams', 'SSO', 'Audit logs'],
    limits: { teams: 5, members_per_team: 25 },
    entitlements: [
      'api_access',
      'custom_domains',
      'custom_branding',
      'manage_teams',
      'manage_members',
      'audit_logs',
    ],
  }),
};

/**
 * Factory for creating plan change preview responses
 */
export function createMockPreviewResponse(
  overrides: Partial<PlanChangePreviewResponse> = {}
): PlanChangePreviewResponse {
  return {
    amount_due: 7000,
    subtotal: 9900,
    credit_applied: 2900,
    next_billing_date: Math.floor(Date.now() / 1000) + 86400 * 30,
    currency: 'usd',
    current_plan: {
      price_id: 'price_current_123',
      amount: 2900,
      interval: 'month',
    },
    new_plan: {
      price_id: 'price_target_456',
      amount: 9900,
      interval: 'month',
    },
    ...overrides,
  };
}

/**
 * Pre-configured preview responses for common scenarios
 */
export const mockPreviewResponses = {
  upgrade: createMockPreviewResponse({
    amount_due: 5000,
    subtotal: 9900,
    credit_applied: 4900,
    immediate_amount: 5000,
    next_period_amount: 9900,
    ending_balance: 0,
    remaining_credit: 0,
    actual_next_billing_due: 9900,
    tax: 0,
  }),
  downgrade: createMockPreviewResponse({
    amount_due: 0,
    subtotal: -4600,
    credit_applied: 6400,
    immediate_amount: -4600,
    next_period_amount: 3500,
    ending_balance: -9900,
    remaining_credit: 9900,
    actual_next_billing_due: 0,
    tax: 0,
    current_plan: {
      price_id: 'price_high',
      amount: 9900,
      interval: 'month',
    },
    new_plan: {
      price_id: 'price_low',
      amount: 3500,
      interval: 'month',
    },
  }),
  withCredit: createMockPreviewResponse({
    amount_due: 0,
    subtotal: 3500,
    credit_applied: 5000,
    immediate_amount: 0,
    next_period_amount: 3500,
    ending_balance: -1500,
    remaining_credit: 1500,
    actual_next_billing_due: 2000,
    tax: 0,
  }),
  withTax: createMockPreviewResponse({
    amount_due: 5695,
    subtotal: 5000,
    credit_applied: 0,
    immediate_amount: 5000,
    next_period_amount: 9900,
    ending_balance: 0,
    remaining_credit: 0,
    actual_next_billing_due: 9900,
    tax: 695,
  }),
};

/**
 * Factory for subscription status responses
 */
export function createMockSubscriptionStatus(
  overrides: Partial<SubscriptionStatusResponse> = {}
): SubscriptionStatusResponse {
  return {
    has_active_subscription: true,
    current_plan: 'identity_plus_v1_monthly',
    current_price_id: 'price_single_monthly',
    subscription_item_id: 'si_test_123',
    subscription_status: 'active',
    current_period_end: Math.floor(Date.now() / 1000) + 86400 * 30,
    ...overrides,
  };
}

/**
 * Pre-configured subscription status variants
 */
export const mockSubscriptionStatuses = {
  active: createMockSubscriptionStatus(),
  inactive: createMockSubscriptionStatus({
    has_active_subscription: false,
    current_plan: null,
    current_price_id: undefined,
    subscription_item_id: undefined,
    subscription_status: undefined,
    current_period_end: undefined,
  }),
  pastDue: createMockSubscriptionStatus({
    subscription_status: 'past_due',
  }),
  canceled: createMockSubscriptionStatus({
    subscription_status: 'canceled',
    has_active_subscription: false,
  }),
  trialing: createMockSubscriptionStatus({
    subscription_status: 'trialing',
    current_period_end: Math.floor(Date.now() / 1000) + 86400 * 14,
  }),
  /**
   * Legacy "identity" plan subscriber - Early Supporter with grandfathered pricing.
   * Note: current_plan is 'identity' (not 'identity_plus_v1_monthly').
   */
  legacyIdentity: createMockSubscriptionStatus({
    current_plan: 'identity',
    current_price_id: undefined, // Legacy plans may not have Stripe price IDs
    subscription_status: 'active',
  }),
};

/**
 * Factory for creating mock organizations with billing data
 */
export function createMockOrganization(overrides: Partial<Organization> = {}): Organization {
  return {
    id: 'org_obj_123' as ObjId,
    extid: 'org_ext_123' as ExtId,
    display_name: 'Test Organization',
    description: 'A test organization',
    contact_email: 'contact@example.com',
    billing_email: 'billing@example.com',
    is_default: true,
    created: new Date('2024-01-01'),
    updated: new Date('2024-01-01'),
    owner_extid: 'cust_ext_456' as ExtId,
    member_count: 5,
    current_user_role: 'owner',
    planid: 'identity_plus_v1_monthly',
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
    limits: {
      teams: 1,
      members_per_team: 10,
      custom_domains: 3,
    },
    ...overrides,
  };
}

/**
 * Pre-configured organization variants
 */
export const mockOrganizations = {
  free: createMockOrganization({
    planid: 'free_v1',
    entitlements: [],
    limits: { teams: 0, members_per_team: 0, custom_domains: 0 },
  }),
  singleTeam: createMockOrganization(),
  multiTeam: createMockOrganization({
    planid: 'team_plus_v1_monthly',
    entitlements: [
      'api_access',
      'custom_domains',
      'custom_branding',
      'manage_teams',
      'manage_members',
      'audit_logs',
    ],
    limits: { teams: 5, members_per_team: 25, custom_domains: 10 },
  }),
  /**
   * Legacy "identity" plan - grandfathered Early Supporter plan
   * These customers have single_team tier features but their planid is just 'identity'
   * (not 'identity_plus_v1_monthly'). Display should show "Identity Plus (Early Supporter)".
   */
  legacyIdentity: createMockOrganization({
    planid: 'identity',
    display_name: 'Early Supporter Org',
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
    limits: { teams: 1, members_per_team: 10, custom_domains: 3 },
  }),
  noOrg: null,
};

/**
 * Mock invoice data
 */
export interface MockInvoice {
  id: string;
  number?: string;
  amount: number;
  currency: string;
  status: 'paid' | 'pending' | 'failed';
  created: number;
  period_start: number;
  period_end: number;
  invoice_pdf?: string | null;
  hosted_invoice_url?: string | null;
}

/**
 * Factory for creating mock invoices
 */
export function createMockInvoice(overrides: Partial<MockInvoice> = {}): MockInvoice {
  const now = Math.floor(Date.now() / 1000);
  return {
    id: 'inv_test_123',
    number: 'INV-001',
    amount: 2900,
    currency: 'usd',
    status: 'paid',
    created: now - 86400 * 30,
    period_start: now - 86400 * 30,
    period_end: now,
    invoice_pdf: 'https://stripe.com/invoice/pdf/inv_test_123',
    hosted_invoice_url: 'https://stripe.com/invoice/inv_test_123',
    ...overrides,
  };
}

/**
 * Pre-configured invoice list
 */
export const mockInvoices: MockInvoice[] = [
  createMockInvoice({ id: 'inv_001', number: 'INV-001', status: 'paid' }),
  createMockInvoice({
    id: 'inv_002',
    number: 'INV-002',
    status: 'pending',
    created: Math.floor(Date.now() / 1000) - 86400 * 60,
    period_start: Math.floor(Date.now() / 1000) - 86400 * 60,
    period_end: Math.floor(Date.now() / 1000) - 86400 * 30,
    invoice_pdf: null,
  }),
  createMockInvoice({
    id: 'inv_003',
    number: 'INV-003',
    status: 'failed',
    created: Math.floor(Date.now() / 1000) - 86400 * 90,
    period_start: Math.floor(Date.now() / 1000) - 86400 * 90,
    period_end: Math.floor(Date.now() / 1000) - 86400 * 60,
    invoice_pdf: null,
    hosted_invoice_url: null,
  }),
];

/**
 * Factory for creating billing overview responses
 */
export function createMockOverviewResponse(
  overrides: Partial<BillingOverviewResponse> = {}
): BillingOverviewResponse {
  return {
    organization: {
      id: 'org_123',
      external_id: 'org_ext_123',
      display_name: 'Test Organization',
      billing_email: null,
    },
    subscription: {
      id: 'sub_123',
      status: 'active',
      period_end: Math.floor(Date.now() / 1000) + 86400 * 30,
      active: true,
      past_due: false,
      canceled: false,
    },
    plan: {
      id: 'identity_plus_v1_monthly',
      name: 'Identity Plus',
      tier: 'single_team',
      interval: 'month',
      amount: 2900,
      currency: 'usd',
      features: ['web.billing.features.feature1', 'web.billing.features.feature2'],
      limits: { teams: 1 },
    },
    usage: { teams: 1, members: 3 },
    ...overrides,
  };
}

/**
 * Pre-configured overview response variants
 */
export const mockOverviewResponses = {
  active: createMockOverviewResponse(),
  free: createMockOverviewResponse({
    subscription: null,
    plan: null,
  }),
  pastDue: createMockOverviewResponse({
    subscription: {
      id: 'sub_123',
      status: 'past_due',
      period_end: Math.floor(Date.now() / 1000) + 86400 * 30,
      active: true,
      past_due: true,
      canceled: false,
    },
  }),
  /**
   * Legacy "identity" plan subscriber - Early Supporter with grandfathered pricing.
   * Plan ID is 'identity' and display name includes "(Early Supporter)" suffix.
   */
  legacyIdentity: createMockOverviewResponse({
    plan: {
      id: 'identity',
      name: 'Identity Plus (Early Supporter)',
      tier: 'single_team',
      interval: 'month',
      amount: 1900,
      currency: 'usd',
      features: ['web.billing.features.feature1', 'web.billing.features.feature2'],
      limits: { teams: 1 },
    },
  }),
};
