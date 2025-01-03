// src/types/declarations/window.d.ts

import {
  AuthenticationSettings,
  AvailablePlans,
  BrokenBrandSettings,
  Customer,
  Plan,
  RegionsConfig,
  SecretOptions,
} from '@/schemas/models';
import { Stripe } from 'stripe';

/**
 * TypeScript declarations for custom window properties injected by the Ruby backend.
 * Extends the global Window interface to provide type safety for server-injected data.
 *
 * Implementation:
 * - Backend injects data via <script> tags in the HTML header
 * - Properties are added to window object at runtime
 * - This declaration file enables TypeScript type checking and IDE support
 */

export interface OnetimeWindow {
  apitoken?: string;
  authenticated: boolean;
  baseuri: string;
  cust: Customer | null;
  custid: string;
  customer_since?: string;
  custom_domains?: string[];
  domains_enabled: boolean;
  email: string;
  frontend_host: string;
  locale: string;
  is_default_locale: boolean;
  supported_locales: string[];
  ot_version: string;
  plans_enabled: boolean;
  regions_enabled: boolean;
  ruby_version: string;

  /**
   * CSRF token for POST request validation.
   * Updated dynamically after POST requests.
   * Use useCsrfStore() to access current token.
   */
  shrimp: string;

  site_host: string;
  stripe_customer?: Stripe.Customer;
  stripe_subscriptions?: Stripe.Subscriptions[];
  form_fields?: { [key: string]: string };
  authentication: AuthenticationSettings | null;
  secret_options: SecretOptions | null;

  available_plans: AvailablePlans;
  support_host?: string;

  plan: Plan;
  is_paid: boolean;
  default_planid: string;

  regions: RegionsConfig;

  incoming_recipient: string;

  available_jurisdictions: string[];

  /**
   * Flag to disable pre-Vue color mode detection
   * after Vue app initialization
   */
  enjoyTheVue: boolean;

  /** Optional HTML banner displayed at page top */
  global_banner?: string;

  canonical_domain: string | null;
  domain_strategy: string;
  domain_id: string;
  display_domain: string;
  domain_branding: BrokenBrandSettings;
}
