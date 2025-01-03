// src/types/declarations/window.d.ts

import {
  AuthenticationSettings,
  AvailablePlans,
  BrokenBrandSettings,
  Customer,
  Metadata,
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
  cust: Customer | undefined | null;
  custid: string;
  customer_since?: string;
  custom_domains_record_count?: number;
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

  // Our CSRF token, to be used in POST requests to the backend. The
  // Ruby app plops the current shrimp at the time of page load into
  // the window object here but it will change if something on the
  // page makes a POST request. Use useCsrfStore() to stay cool and current.
  shrimp: string;

  site_host: string;
  stripe_customer?: Stripe.Customer;
  stripe_subscriptions?: Stripe.Subscriptions[];
  form_fields?: { [key: string]: string };
  authentication: AuthenticationSettings;
  secret_options: SecretOptions | undefined | null;

  available_plans: AvailablePlans;
  support_host?: string;

  // Display site links in footer
  display_links: boolean;

  // Display logo and top nav
  display_masthead: boolean;

  metadata_record_count: number;

  plan: Plan;
  is_paid: boolean;
  default_planid: string;

  received: Metadata[];
  notreceived: Metadata[];
  has_items: boolean;

  regions: RegionsConfig;

  incoming_recipient: string;

  available_jurisdictions: string[];

  // Used by the pre-Vue colour mode detection to go inert once
  // the Vue app takes control over the UI. See index.html.
  enjoyTheVue: boolean;

  // When present, the global banner is displayed at the top of the
  // page. NOTE: Can contain HTML.
  global_banner?: string;

  canonical_domain: string | null;
  domain_strategy: string;
  domain_id: string;
  display_domain: string;
  domain_branding: BrokenBrandSettings;
}
