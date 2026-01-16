// src/services/billing.service.ts

/**
 * Billing Service
 *
 * Provides methods for interacting with the billing API endpoints.
 * Handles organization subscriptions, checkout sessions, and invoices.
 */

import { createApi } from '@/api';
import type { Invoice, PaymentMethod } from '@/types/billing';

const $api = createApi();

/**
 * Billing overview response from the API
 */
export interface BillingOverviewResponse {
  organization: {
    id: string;
    external_id: string;
    display_name: string;
    billing_email: string | null;
  };
  subscription: {
    id: string;
    status: string;
    period_end: number;
    active: boolean;
    past_due: boolean;
    canceled: boolean;
  } | null;
  plan: {
    id: string;
    name: string;
    tier: string;
    interval: string;
    amount: number;
    currency: string;
    features: string[];
    limits: Record<string, number>;
  } | null;
  usage: {
    teams: number;
    members: number;
  };
  payment_method?: PaymentMethod;
}

/**
 * Checkout session response
 */
export interface CheckoutSessionResponse {
  checkout_url: string;
  session_id: string;
}

/**
 * Invoices list response
 */
export interface InvoicesResponse {
  invoices: Invoice[];
  has_more: boolean;
}

/**
 * Plan data from the API
 */
export interface Plan {
  id: string;
  /** Stripe price ID for plan switching operations */
  stripe_price_id: string;
  name: string;
  tier: string;
  interval: string;
  amount: number;
  currency: string;
  region: string;
  display_order: number;
  /** Feature locale keys (e.g., "web.billing.features.custom_domains") */
  features: string[];
  limits: Record<string, number>;
  entitlements: string[];
  /** For grouping monthly/yearly variants of the same plan */
  plan_code?: string;
  /** Whether this plan should display "Most Popular" badge */
  is_popular?: boolean;
  /** For yearly plans: the monthly equivalent price for display */
  monthly_equivalent_amount?: number;
  /** Display label next to plan name (e.g., "For Teams"). Null/empty = hide label */
  plan_name_label?: string | null;
  /** Reference to parent plan ID for "Includes everything in X, plus:" display */
  includes_plan?: string;
  /** Human-readable name of included plan (resolved by backend) */
  includes_plan_name?: string;
}

/**
 * Plans list response
 */
export interface PlansResponse {
  plans: Plan[];
}

/**
 * Subscription status response
 */
export interface SubscriptionStatusResponse {
  has_active_subscription: boolean;
  current_plan: string | null;
  current_price_id?: string;
  subscription_item_id?: string;
  subscription_status?: string;
  current_period_end?: number;
}

/**
 * Plan change preview response (proration details)
 */
export interface PlanChangePreviewResponse {
  amount_due: number;
  subtotal: number;
  credit_applied: number;
  next_billing_date: number | null;
  currency: string;
  current_plan: {
    price_id: string;
    amount: number;
    interval: string;
  };
  new_plan: {
    price_id: string;
    amount: number;
    interval: string;
  };
  /** Amount charged today (proration). New field - may not be present in older API responses */
  immediate_amount?: number;
  /** Regular subscription amount for the next billing period. New field - may not be present in older API responses */
  next_period_amount?: number;
  /** Ending balance after invoice. Negative = credit remaining on account */
  ending_balance?: number;
  /** Tax amount on this invoice */
  tax?: number;
  /** Convenience field: absolute value of ending_balance when negative (credit remaining) */
  remaining_credit?: number;
  /** What customer will actually pay at next billing (after credits applied) */
  actual_next_billing_due?: number;
}

/**
 * Plan change result response
 */
export interface PlanChangeResponse {
  success: boolean;
  new_plan: string;
  status: string;
  current_period_end: number;
}

export const BillingService = {
  /**
   * Get billing overview for an organization
   *
   * @param orgExtId - Organization external ID
   * @returns Billing overview data including subscription, plan, and usage
   */
  async getOverview(orgExtId: string): Promise<BillingOverviewResponse> {
    const response = await $api.get(`/billing/api/org/${orgExtId}`);
    return response.data;
  },

  /**
   * Create a checkout session for subscribing to or changing a plan
   *
   * Terminology:
   * - `product`: The plan product ID without interval suffix (e.g., 'identity_plus_v1')
   * - `interval`: The billing interval ('month' or 'year')
   *
   * The product is derived from plan.id by removing the interval suffix.
   *
   * @param orgExtId - Organization external ID
   * @param plan - Plan object with id and interval
   * @returns Checkout session URL and ID
   */
  async createCheckoutSession(
    orgExtId: string,
    plan: { id: string; interval: string }
  ): Promise<CheckoutSessionResponse> {
    // Derive product from plan.id by removing interval suffix
    // plan.id = 'identity_plus_v1_monthly' → product = 'identity_plus_v1'
    const intervalSuffix = plan.interval === 'year' ? '_yearly' : '_monthly';
    const product = plan.id.endsWith(intervalSuffix)
      ? plan.id.slice(0, -intervalSuffix.length)
      : plan.id;

    const response = await $api.post(`/billing/api/org/${orgExtId}/checkout`, {
      product,
      interval: plan.interval,
    });
    return response.data;
  },

  /**
   * List invoices for an organization
   *
   * @param orgExtId - Organization external ID
   * @returns List of invoices with pagination info
   */
  async listInvoices(orgExtId: string): Promise<InvoicesResponse> {
    const response = await $api.get(`/billing/api/org/${orgExtId}/invoices`);
    return response.data;
  },

  /**
   * List all available billing plans
   *
   * @returns List of available plans with pricing and features
   */
  async listPlans(): Promise<PlansResponse> {
    const response = await $api.get('/billing/api/plans');
    return response.data;
  },

  /**
   * Get subscription status for an organization
   *
   * Determines whether the organization has an active subscription
   * and returns current plan details if so.
   *
   * @param orgExtId - Organization external ID
   * @returns Subscription status including current plan and price details
   */
  async getSubscriptionStatus(orgExtId: string): Promise<SubscriptionStatusResponse> {
    const response = await $api.get(`/billing/api/org/${orgExtId}/subscription`);
    return response.data;
  },

  /**
   * Preview plan change proration
   *
   * Shows what the customer will be charged when switching plans,
   * including credits and prorated amounts.
   *
   * @param orgExtId - Organization external ID
   * @param newPriceId - Stripe price ID to switch to
   * @returns Proration preview with amounts and billing details
   */
  async previewPlanChange(
    orgExtId: string,
    newPriceId: string
  ): Promise<PlanChangePreviewResponse> {
    const response = await $api.post(`/billing/api/org/${orgExtId}/preview-plan-change`, {
      new_price_id: newPriceId,
    });
    return response.data;
  },

  /**
   * Execute plan change
   *
   * Changes the organization's subscription to a new plan.
   * Uses immediate proration (customer charged/credited on next invoice).
   *
   * @param orgExtId - Organization external ID
   * @param newPriceId - Stripe price ID to switch to
   * @returns Result of plan change with new plan details
   */
  async changePlan(orgExtId: string, newPriceId: string): Promise<PlanChangeResponse> {
    const response = await $api.post(`/billing/api/org/${orgExtId}/change-plan`, {
      new_price_id: newPriceId,
    });
    return response.data;
  },
};
