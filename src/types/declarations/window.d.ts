// src/types/declarations/window.d.ts

import {
  AuthenticationSettings,
  BrandSettings,
  Customer,
  ImageProps,
  Locale,
  RegionsConfig,
  SecretOptions,
} from '@/schemas/models';
import { Stripe } from 'stripe';
import { FallbackLocale } from 'vue-i18n';
import { DiagnosticsConfig } from '../diagnostics';

/**
 * TypeScript declarations for custom window properties injected by
 * the Ruby backend. These properties are used to pass data from the
 * backend to the frontend. The properties are added to the window object
 * each time a full page load is performed.
 *
 * The corresponding Ruby backend code can be found in:
 * lib/onetime/app/web/views/base.rb
 *
 * Implementation:
 * - Backend injects data via JSON <script> tag in the HTML header
 * - Properties are added to window.__ONETIME_STATE__
 * - This declaration file enables TypeScript type checking and IDE support
 */

type Message = { type: 'success' | 'error' | 'info'; content: string };

export interface FooterLink {
  text?: string;
  i18n_key?: string;
  url: string;
  external?: boolean;
  icon?: string;
}

export interface FooterGroup {
  name?: string;
  i18n_key?: string;
  links: FooterLink[];
}

export interface FooterLinksConfig {
  enabled: boolean;
  groups: FooterGroup[];
}

export interface HeaderLogo {
  url: string;
  alt: string;
  link_to: string;
}

export interface HeaderBranding {
  logo: HeaderLogo;
  site_name?: string;
}

export interface HeaderNavigation {
  enabled: boolean;
}

export interface HeaderConfig {
  enabled: boolean;
  branding?: HeaderBranding;
  navigation?: HeaderNavigation;
}

export interface UiInterface {
  enabled: boolean;
  header?: HeaderConfig;
  footer_links?: FooterLinksConfig;
}

export interface OnetimeWindow {
  apitoken?: string;

  /**
   * User is fully authenticated (all auth factors complete).
   * When true, user has full access to their account.
   */
  authenticated: boolean;

  /**
   * User is partially authenticated and awaiting MFA completion.
   * When true, user has passed first factor (email/password) but needs
   * to complete second factor (TOTP/WebAuthn) before full access.
   * The user menu will appear with an amber badge during this state.
   */
  awaiting_mfa: boolean;
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
  supported_locales: Locale[];
  fallback_locale: FallbackLocale;
  default_locale: Locale;

  ot_version: string;
  ot_version_long: string;
  billing_enabled: boolean;
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

  features: {
    markdown: boolean;
  };

  ui: UiInterface;
}
