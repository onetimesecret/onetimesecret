// src/types/declarations/bootstrap.d.ts

/**
 * Schema imports for bootstrap payload types.
 *
 * All imports currently use v2 shapes. Migration to v3 shapes requires:
 *
 * 1. Customer → CustomerRecord: V3 uses native types (number timestamps → Date),
 *    but bootstrap stores expect the output type. Would need Zod parsing integration.
 *
 * 2. BrandSettings → BrandSettingsRecord: V3 has required boolean fields (via Zod
 *    defaults), but bootstrapStore uses `{} as BrandSettings` which requires all
 *    fields optional. V2 uses `.partial()` making all fields optional.
 *
 * 3. Config shapes (AuthenticationSettings, RegionsConfig, SecretOptions, Locale):
 *    These are re-exported from shapes/config and i18n modules. No v3 equivalents
 *    exist since they're configuration shapes, not entity shapes.
 *
 * TODO(#2686): Migrate to v3 shapes once bootstrap parsing integrates Zod validation.
 */
import {
  AuthenticationSettings,
  BrandSettings,
  Customer,
  Locale,
  RegionsConfig,
  SecretOptions,
} from '@/schemas/shapes/v2';
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
 * apps/web/core/views/serializers/
 *
 * Implementation:
 * - Backend serializers produce data (see SerializerRegistry)
 * - Rhales injects via JSON <script> tag in the HTML header
 * - Properties are added to window.__BOOTSTRAP_STATE__
 * - This declaration file enables TypeScript type checking and IDE support
 *
 * Schema Principle:
 * Bootstrap is internal communication between our backend and frontend —
 * we have 100% control over both sides. Therefore:
 * - Use modern v3 shapes with native types (boolean, number, Date)
 * - No string-encoded booleans or legacy field names
 * - No backwards compatibility layers or deprecation shims
 * - Keep fields current; remove unused fields promptly
 *
 * When adding/modifying fields, update both:
 * - This file (frontend types)
 * - The relevant serializer in apps/web/core/views/serializers/
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

  /**
   * Whether the authenticated account has a password set.
   * SSO-only accounts (Entra, Google, GitHub) have no password.
   * Used to hide security settings (password change, MFA, recovery codes)
   * that are irrelevant for SSO-only users.
   */
  has_password?: boolean;

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
    /** Multi-factor authentication (TOTP + recovery codes) */
    mfa?: boolean;
    /** Account lockout after failed login attempts */
    lockout?: boolean;
    /** Password complexity requirements enforcement */
    password_requirements?: boolean;
    /** Email-based authentication (magic links) */
    email_auth?: boolean;
    /** WebAuthn/passkey authentication */
    webauthn?: boolean;
    /**
     * SSO authentication via external identity providers (Entra ID, Google, GitHub, etc.).
     * Can be boolean (false when disabled) or object with config when enabled.
     */
    sso?: boolean | {
      enabled: boolean;
      /** Configured SSO providers. Each entry has route_name and display_name. */
      providers?: Array<{
        route_name: string;
        display_name: string;
      }>;
    };
    /**
     * SSO-only mode. When true, password-based auth routes are disabled
     * and the sign-in page shows only SSO provider buttons.
     * This is a no-op when SSO is not enabled (sso feature is falsy).
     */
    sso_only?: boolean;
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
