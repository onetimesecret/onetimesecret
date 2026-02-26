// src/services/billing.service.ts

/**
 * Billing Service
 *
 * Provides methods for interacting with the billing API endpoints.
 * Handles organization subscriptions, checkout sessions, and invoices.
 */

import { createApi } from '@/api';
import type { PaymentMethod } from '@/types/billing';
import type {
  CurrencyConflictError,
  InvoiceStatus,
  MigrateCurrencyRequest,
  MigrateCurrencyResponse,
} from '@/schemas/models/billing';

const $api = createApi();

/**
 * Billing overview response from the API
 */
/**
 * Federation notification data for cross-region subscription sync
 */
export interface FederationNotification {
  show: boolean;
  source_region?: string;
}

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
    members: number;
    domains: number;
  };
  payment_method?: PaymentMethod;
  /** Federation notification for cross-region subscription sync */
  federation_notification?: FederationNotification;
}

/**
 * Checkout session response
 */
export interface CheckoutSessionResponse {
  checkout_url: string;
  session_id: string;
}

/**
 * Invoice data as returned by the billing API.
 *
 * Matches the shape from GET /billing/api/org/:extid/invoices.
 * Note: This differs from the Zod `Invoice` schema in schemas/models/billing.ts
 * which defines an idealized shape. This interface matches the actual API response.
 */
export interface StripeInvoice {
  id: string;
  number: string | null;
  amount: number;
  currency: string;
  status: InvoiceStatus;
  created: number;
  due_date: number | null;
  paid_at: number | null;
  invoice_pdf: string | null;
  hosted_invoice_url: string | null;
}

/**
 * Invoices list response
 */
export interface InvoicesResponse {
  invoices: StripeInvoice[];
  has_more: boolean;
}

/**
 * Plan data from the API
 */
export interface Plan {
  id: string;
  /** Stripe price ID for plan switching operations. Null for free/config-only plans. */
  stripe_price_id: string | null;
  name: string;
  tier: string;
  interval: string;
  amount: number;
  currency: string;
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
  /** Region identifier from Stripe product metadata */
  region?: string;
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
  /** Currency of the current subscription (e.g., 'usd', 'eur') */
  current_currency?: string;
  /** True if subscription is scheduled for cancellation at period end */
  cancel_at_period_end?: boolean;
  /** Unix timestamp when subscription will be cancelled (if scheduled) */
  cancel_at?: number | null;
  /** Present when a currency migration is pending (graceful mode) */
  pending_currency_migration?: {
    target_price_id: string;
    target_plan_name: string;
    target_currency: string;
    target_plan_id: string;
    effective_after: number;
  } | null;
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

/**
 * Cancel subscription result response
 */
export interface CancelSubscriptionResponse {
  success: boolean;
  /** Unix timestamp when subscription will end */
  cancel_at: number;
  /** Current subscription status (typically 'active' until period ends) */
  status: string;
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

  /**
   * Cancel subscription
   *
   * Cancels the organization's subscription at the end of the current billing period.
   * The subscription remains active until the period ends, then downgrades to free tier.
   *
   * @param orgExtId - Organization external ID
   * @returns Result of cancellation with effective date
   */
  async cancelSubscription(orgExtId: string): Promise<CancelSubscriptionResponse> {
    const response = await $api.post(`/billing/api/org/${orgExtId}/cancel-subscription`);
    return response.data;
  },

  /**
   * Migrate subscription to a new currency
   *
   * Handles the case where a customer's existing Stripe subscription uses
   * a different currency than the target plan. Two modes:
   * - 'graceful': Cancel at period end; user completes new checkout later
   * - 'immediate': Cancel now with prorated refund; redirect to new checkout
   *
   * @param orgExtId - Organization external ID
   * @param request - Migration parameters (price ID and mode)
   * @returns Migration result (shape varies by mode)
   */
  async migrateCurrency(
    orgExtId: string,
    request: MigrateCurrencyRequest
  ): Promise<MigrateCurrencyResponse> {
    const response = await $api.post(
      `/billing/api/org/${orgExtId}/migrate-currency`,
      request
    );
    return response.data;
  },
};

/**
 * Check if an error response indicates a currency conflict.
 *
 * Currency conflicts occur when a customer tries to subscribe to a plan
 * in a different currency than their existing Stripe subscription.
 * The backend returns HTTP 409 with `code: 'currency_conflict'`.
 *
 * @param error - The caught error from an API call
 * @returns The conflict details if this is a currency conflict, null otherwise
 */
export function extractCurrencyConflict(error: unknown): CurrencyConflictError | null {
  if (
    typeof error === 'object' &&
    error !== null &&
    'response' in error
  ) {
    const axiosError = error as { response?: { status?: number; data?: Record<string, unknown> } };
    const data = axiosError.response?.data;

    if (
      axiosError.response?.status === 409 &&
      data &&
      data.code === 'currency_conflict'
    ) {
      return data as unknown as CurrencyConflictError;
    }
  }
  return null;
}
