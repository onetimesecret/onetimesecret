// src/types/declarations/bootstrap.d.ts

import {
  AuthenticationSettings,
  BrandSettings,
  Customer,
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
 * - Properties are added to window.__BOOTSTRAP_STATE__
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

/**
 * BootstrapPayload is the canonical type name for server-injected state.
 * BootstrapPayload is preserved as an alias for backwards compatibility.
 */
export interface BootstrapPayload {
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

  /**
   * Indicates whether the request had a valid session at the time of response.
   * This is crucial for error pages where authenticated=false but the user
   * had a valid session. The frontend uses this to preserve auth state and
   * avoid incorrect redirects to signin on server errors.
   */
  had_valid_session: boolean;

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
  billing_enabled?: boolean;
  regions_enabled: boolean;
  ruby_version: string;

  /**
   * CSRF token for POST request validation.
   * Updated dynamically after POST requests.
   * Use useCsrfStore() to access current token.
   */
  shrimp: string;

  site_host: string;
  support_host: string;

  /** Brand primary color from server config (hex string, e.g. '#dc4a22') */
  brand_primary_color?: string;
  /** Brand product name from server config (e.g. 'Onetime Secret') */
  brand_product_name?: string;
  /** Brand corner style from server config ('rounded' | 'pill' | 'square') */
  brand_corner_style?: string;
  /** Brand font family from server config ('sans' | 'serif' | 'mono') */
  brand_font_family?: string;
  /** Whether brand buttons use light text (default: true) */
  brand_button_text_light?: boolean;
  /** Whether public homepage is allowed (default: true) */
  brand_allow_public_homepage?: boolean;
  /** Whether public API access is allowed (default: true) */
  brand_allow_public_api?: boolean;

  /** Documentation site host from server config (e.g. 'docs.onetimesecret.com') */
  docs_host?: string;

  stripe_customer?: Stripe.Customer;
  stripe_subscriptions?: Stripe.Subscriptions[];
  authentication: AuthenticationSettings; // TODO: May need to offer default values
  secret_options: SecretOptions;

  regions: RegionsConfig;

  available_jurisdictions: string[];

  /**
   * Flag to disable pre-Vue color mode detection
   * after Vue app initialization
   */
  enjoyTheVue: boolean;

  /**
   * Homepage mode indicating accessibility state.
   * - 'protected': Homepage is accessible (bypass header present)
   * - null/undefined: No special mode, follow authentication.required
   */
  homepage_mode?: 'external' | 'internal' | null;

  /** Optional HTML banner displayed at page top */
  global_banner?: string;

  canonical_domain: string;
  domain_strategy: 'canonical' | 'subdomain' | 'custom' | 'invalid';
  domain_id: string;
  display_domain: string;
  domain_branding: BrandSettings;
  /** URL to custom domain logo image, or null if no logo uploaded */
  domain_logo: string | null;
  /** User's preferred domain context from session (server-side preference) */
  domain_context?: string | null;

  messages: Message[];

  d9s_enabled: boolean;
  diagnostics: DiagnosticsConfig;

  /** Development mode configuration */
  development?: {
    enabled: boolean;
    /** When true, enables domain context override feature in Colonel */
    domain_context_enabled: boolean;
  };

  features: {
    markdown: boolean;
    /** Account lockout after failed login attempts */
    lockout?: boolean;
    /** Password complexity requirements enforcement */
    password_requirements?: boolean;
    /** Email-based authentication (magic links) */
    email_auth?: boolean;
    /** WebAuthn/passkey authentication */
    webauthn?: boolean;
    /**
     * OmniAuth/SSO authentication via external identity providers.
     * Can be boolean (false when disabled) or object with config when enabled.
     */
    omniauth?: boolean | {
      enabled: boolean;
      /** Display name for the SSO provider (e.g., "Zitadel", "Okta") */
      display_name?: string;
      /** @deprecated Use display_name instead */
      provider_name?: string;
      /** OmniAuth strategy route name (e.g., "oidc", "saml", "google_oauth2") */
      route_name?: string;
    };
    /** @deprecated Use email_auth instead */
    magic_links?: boolean;
  };

  ui: UiInterface;

  /**
   * Entitlement test mode (colonel only)
   * Allows testing with different plan entitlements temporarily.
   * entitlement_test_planid being set indicates test mode is active.
   */
  entitlement_test_planid?: string | null;
  entitlement_test_plan_name?: string | null;

  /**
   * Current user's organization (when authenticated)
   * Populated by OrganizationSerializer from OrganizationLoader context
   */
  organization?: {
    /** Internal organization ID (use for store lookups, Vue :key) */
    id: string;
    /** External organization ID (use for API paths, URLs) */
    extid: string;
    /** Display name for the organization */
    display_name: string;
    /** Whether this is the user's default workspace */
    is_default: boolean;
    /** Plan identifier for entitlement checks */
    planid?: string | null;
    /** Current user's role in this organization */
    current_user_role?: 'owner' | 'admin' | 'member' | null;
  } | null;
}

/**
 * BootstrapPayload is the preferred type name for server-injected state.
 * Alias for BootstrapPayload - use either interchangeably.
 */
export type BootstrapPayload = BootstrapPayload;
