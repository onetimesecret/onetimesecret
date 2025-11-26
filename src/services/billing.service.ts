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
  name: string;
  tier: string;
  interval: string;
  amount: number;
  currency: string;
  region: string;
  display_order: number;
  features: string[];
  limits: Record<string, number>;
  capabilities: string[];
}

/**
 * Plans list response
 */
export interface PlansResponse {
  plans: Plan[];
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
   * @param orgExtId - Organization external ID
   * @param tier - Plan tier (e.g., 'single_team', 'multi_team')
   * @param billingCycle - Billing cycle ('month' or 'year')
   * @returns Checkout session URL and ID
   */
  async createCheckoutSession(
    orgExtId: string,
    tier: string,
    billingCycle: string
  ): Promise<CheckoutSessionResponse> {
    const response = await $api.post(`/billing/api/org/${orgExtId}/checkout`, {
      tier,
      billing_cycle: billingCycle,
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
};
