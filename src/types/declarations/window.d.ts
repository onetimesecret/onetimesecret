// src/types/declarations/window.d.ts

import {
  AuthenticationSettings,
  AvailablePlans,
  BrandSettings,
  Customer,
  ImageProps,
  Locale,
  Plan,
  RegionsConfig,
  SecretOptions,
} from '@/schemas/models';
import { DiagnosticsConfig } from '../diagnostics';
import { Stripe } from 'stripe';
import { FallbackLocale } from 'vue-i18n';

/**
 * TypeScript declarations for custom window properties injected by the Ruby backend.
 * Extends the global Window interface to provide type safety for server-injected data.
 *
 * The backend injects data as json via <script> tag in the HTML header.
 */

type Message = { type: 'success' | 'error' | 'info'; content: string };

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

  i18n_enabled: boolean;
  locale: string;
  is_default_locale: boolean;
  supported_locales: Locale[];
  fallback_locale: FallbackLocale;
  default_locale: Locale;

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
  authentication: AuthenticationSettings; // TODO: May need to offer default values
  secret_options: SecretOptions;

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

  canonical_domain: string;
  domain_strategy: 'canonical' | 'subdomain' | 'custom' | 'invalid';
  domain_id: string;
  display_domain: string;
  domain_branding: BrandSettings;
  domain_logo: ImageProps;

  messages: Message[];

  d9s_enabled: boolean;
  diagnostics: DiagnosticsConfig;
}
