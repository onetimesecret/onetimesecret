// src/shared/stores/bootstrapStore.ts

import type { Locale } from '@/schemas/i18n/locale';
import type {
  AuthenticationSettings,
  BrandSettings,
  Customer,
  RegionsConfig,
  SecretOptions,
} from '@/schemas/models';
import { getBootstrapSnapshot } from '@/services/bootstrap.service';
import type {
  BootstrapPayload,
  FooterLinksConfig,
  HeaderConfig,
  UiInterface,
} from '@/types/declarations/bootstrap';
import type { DiagnosticsConfig } from '@/types/diagnostics';
import { defineStore } from 'pinia';
import { computed, Ref, ref } from 'vue';
import type { FallbackLocale } from 'vue-i18n';

/**
 * Default values for logged-out / initial state.
 *
 * These defaults represent the minimal state needed for a non-authenticated
 * user. When the user logs out, the store resets to these values.
 *
 * Type-safe defaults ensure the store always has valid values even before
 * server data is hydrated.
 */
const DEFAULTS: BootstrapPayload = {
  // Authentication state
  authenticated: false,
  awaiting_mfa: false,
  had_valid_session: false,

  // User identity (null/empty when logged out)
  cust: null,
  custid: '',
  email: '',
  customer_since: undefined,
  apitoken: undefined,

  // Locale settings
  i18n_enabled: true,
  locale: 'en',
  supported_locales: [],
  fallback_locale: 'en',
  default_locale: { code: 'en', name: 'English', enabled: true },

  // Site configuration
  baseuri: '',
  frontend_host: '',
  site_host: '',
  ot_version: '',
  ot_version_long: '',
  ruby_version: '',
  shrimp: '',

  // Feature flags
  billing_enabled: false,
  regions_enabled: false,
  domains_enabled: false,
  d9s_enabled: false,
  enjoyTheVue: false,

  // Domain configuration
  canonical_domain: '',
  domain_strategy: 'canonical',
  domain_id: '',
  display_domain: '',
  domain_branding: {} as BrandSettings,
  domain_logo: null,
  domain_context: null,
  custom_domains: [],

  // Regions configuration
  regions: {
    identifier: '',
    enabled: false,
    current_jurisdiction: '',
    jurisdictions: [],
  },
  available_jurisdictions: [],

  // Authentication settings
  authentication: {
    enabled: true,
    signup: true,
    signin: true,
    autoverify: false,
    required: false,
  },

  // Secret options
  secret_options: {
    default_ttl: 604800,
    ttl_options: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000],
  },

  // Diagnostics
  diagnostics: {
    sentry: {
      dsn: '',
      enabled: false,
      logErrors: true,
      trackComponents: true,
    },
  },

  // UI configuration
  ui: {
    enabled: true,
    header: {
      enabled: true,
    },
    footer_links: {
      enabled: false,
      groups: [],
    },
  },

  // Features
  features: {
    markdown: false,
  },

  // Messages
  messages: [],

  // Homepage and banner
  homepage_mode: null,
  global_banner: undefined,

  // Development mode
  development: undefined,

  // Stripe (billing)
  stripe_customer: undefined,
  stripe_subscriptions: undefined,

  // Entitlement testing (colonel)
  entitlement_test_planid: undefined,
  entitlement_test_plan_name: undefined,

  // Organization
  organization: undefined,
};

/**
 * Helper to conditionally update a ref if the source value is defined.
 * Reduces complexity in hydration functions.
 */
function updateIfDefined<T>(target: Ref<T>, value: T | undefined): void {
  if (value !== undefined) {
    target.value = value;
  }
}

/**
 * Bootstrap Store - Centralized Server State
 *
 * This store replaces the WindowService dual-state pattern with a single
 * Pinia store that holds all server-injected configuration and user state.
 *
 * Design decisions:
 * 1. Individual refs (not reactive object) for granular reactivity
 *    - Computed properties only re-run when their specific ref changes
 *    - Prevents unnecessary re-renders when unrelated fields update
 *
 * 2. Typed defaults for logged-out state
 *    - Store is always in a valid state
 *    - $reset() returns to known good defaults
 *
 * 3. Single source of truth
 *    - No more window.__BOOTSTRAP_STATE__ vs reactiveState synchronization
 *    - All access goes through this store after initialization
 *
 * Lifecycle:
 * - init() called once during app bootstrap (after Pinia is installed)
 * - update() called after /bootstrap/me API responses
 * - refresh() fetches fresh state from server (use after mutations)
 * - $reset() called on logout to restore defaults
 *
 * Access Patterns:
 * Pinia setup stores auto-unwrap refs, so access patterns differ by context:
 *
 * 1. Direct store access (routes, composables, non-reactive JS):
 *    ```ts
 *    const store = useBootstrapStore();
 *    if (store.billing_enabled) { ... }  // No .value needed
 *    ```
 *
 * 2. Reactive destructuring (Vue components needing reactivity):
 *    ```ts
 *    const { billing_enabled } = storeToRefs(store);
 *    if (billing_enabled.value) { ... }  // .value required
 *    ```
 *
 * 3. Template usage (either pattern works without .value):
 *    ```vue
 *    <div v-if="store.billing_enabled">  // Direct access
 *    <div v-if="billing_enabled">        // After storeToRefs destructure
 *    ```
 */
/* eslint-disable max-lines-per-function */
export const useBootstrapStore = defineStore('bootstrap', () => {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE - Individual refs for granular reactivity
  // ═══════════════════════════════════════════════════════════════════════════

  // Authentication state
  const authenticated = ref<boolean>(DEFAULTS.authenticated);
  const awaiting_mfa = ref<boolean>(DEFAULTS.awaiting_mfa);
  const had_valid_session = ref<boolean>(DEFAULTS.had_valid_session);

  // User identity
  const cust = ref<Customer | null>(DEFAULTS.cust);
  const custid = ref<string>(DEFAULTS.custid);
  const email = ref<string>(DEFAULTS.email);
  const customer_since = ref<string | undefined>(DEFAULTS.customer_since);
  const apitoken = ref<string | undefined>(DEFAULTS.apitoken);

  // Locale settings
  const i18n_enabled = ref<boolean>(DEFAULTS.i18n_enabled);
  const locale = ref<string>(DEFAULTS.locale);
  const supported_locales = ref<Locale[]>(DEFAULTS.supported_locales);
  const fallback_locale = ref<FallbackLocale>(DEFAULTS.fallback_locale);
  const default_locale = ref<Locale>(DEFAULTS.default_locale);

  // Site configuration
  const baseuri = ref<string>(DEFAULTS.baseuri);
  const frontend_host = ref<string>(DEFAULTS.frontend_host);
  const site_host = ref<string>(DEFAULTS.site_host);
  const ot_version = ref<string>(DEFAULTS.ot_version);
  const ot_version_long = ref<string>(DEFAULTS.ot_version_long);
  const ruby_version = ref<string>(DEFAULTS.ruby_version);
  const shrimp = ref<string>(DEFAULTS.shrimp);

  // Feature flags
  const billing_enabled = ref<boolean | undefined>(DEFAULTS.billing_enabled);
  const regions_enabled = ref<boolean>(DEFAULTS.regions_enabled);
  const domains_enabled = ref<boolean>(DEFAULTS.domains_enabled);
  const d9s_enabled = ref<boolean>(DEFAULTS.d9s_enabled);
  const enjoyTheVue = ref<boolean>(DEFAULTS.enjoyTheVue);

  // Domain configuration
  const canonical_domain = ref<string>(DEFAULTS.canonical_domain);
  const domain_strategy = ref<BootstrapPayload['domain_strategy']>(DEFAULTS.domain_strategy);
  const domain_id = ref<string>(DEFAULTS.domain_id);
  const display_domain = ref<string>(DEFAULTS.display_domain);
  const domain_branding = ref<BrandSettings>(DEFAULTS.domain_branding);
  const domain_logo = ref<string | null>(DEFAULTS.domain_logo);
  const domain_context = ref<string | null>(DEFAULTS.domain_context ?? null as string | null);
  const custom_domains = ref<string[] | undefined>(DEFAULTS.custom_domains);

  // Regions configuration
  const regions = ref<RegionsConfig>(DEFAULTS.regions);
  const available_jurisdictions = ref<string[]>(DEFAULTS.available_jurisdictions);

  // Authentication settings
  const authentication = ref<AuthenticationSettings>(DEFAULTS.authentication);

  // Secret options
  const secret_options = ref<SecretOptions>(DEFAULTS.secret_options);

  // Diagnostics
  const diagnostics = ref<DiagnosticsConfig>(DEFAULTS.diagnostics);

  // UI configuration
  const ui = ref<UiInterface>(DEFAULTS.ui);

  // Features
  const features = ref<BootstrapPayload['features']>(DEFAULTS.features);

  // Messages
  const messages = ref<BootstrapPayload['messages']>(DEFAULTS.messages);

  // Homepage and banner
  const homepage_mode = ref<BootstrapPayload['homepage_mode']>(DEFAULTS.homepage_mode);
  const global_banner = ref<string | undefined>(DEFAULTS.global_banner);

  // Development mode
  const development = ref<BootstrapPayload['development']>(DEFAULTS.development);

  // Stripe (billing)
  const stripe_customer = ref<BootstrapPayload['stripe_customer']>(DEFAULTS.stripe_customer);
  const stripe_subscriptions = ref<BootstrapPayload['stripe_subscriptions']>(
    DEFAULTS.stripe_subscriptions
  );

  // Entitlement testing (colonel)
  const entitlement_test_planid = ref<string | null | undefined>(DEFAULTS.entitlement_test_planid);
  const entitlement_test_plan_name = ref<string | null | undefined>(
    DEFAULTS.entitlement_test_plan_name
  );

  // Organization
  const organization = ref<BootstrapPayload['organization']>(DEFAULTS.organization);

  // Internal state
  const _initialized = ref(false);

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS - Computed properties for derived state
  // ═══════════════════════════════════════════════════════════════════════════

  const isInitialized = computed(() => _initialized.value);

  /**
   * Header configuration from UI settings.
   * Provides typed access to header config with fallback.
   */
  const headerConfig = computed<HeaderConfig | undefined>(() => ui.value.header);

  /**
   * Footer links configuration from UI settings.
   * Provides typed access to footer config with fallback.
   */
  const footerLinksConfig = computed<FooterLinksConfig | undefined>(() => ui.value.footer_links);

  // ═══════════════════════════════════════════════════════════════════════════
  // HYDRATION HELPERS - Split to reduce complexity
  // ═══════════════════════════════════════════════════════════════════════════

  function hydrateAuthState(data: Partial<BootstrapPayload>): void {
    updateIfDefined(authenticated, data.authenticated);
    updateIfDefined(awaiting_mfa, data.awaiting_mfa);
    updateIfDefined(had_valid_session, data.had_valid_session);
  }

  function hydrateUserIdentity(data: Partial<BootstrapPayload>): void {
    updateIfDefined(cust, data.cust);
    updateIfDefined(custid, data.custid);
    updateIfDefined(email, data.email);
    updateIfDefined(customer_since, data.customer_since);
    updateIfDefined(apitoken, data.apitoken);
  }

  function hydrateLocaleSettings(data: Partial<BootstrapPayload>): void {
    updateIfDefined(i18n_enabled, data.i18n_enabled);
    updateIfDefined(locale, data.locale);
    updateIfDefined(supported_locales, data.supported_locales);
    updateIfDefined(fallback_locale, data.fallback_locale);
    updateIfDefined(default_locale, data.default_locale);
  }

  function hydrateSiteConfig(data: Partial<BootstrapPayload>): void {
    updateIfDefined(baseuri, data.baseuri);
    updateIfDefined(frontend_host, data.frontend_host);
    updateIfDefined(site_host, data.site_host);
    updateIfDefined(ot_version, data.ot_version);
    updateIfDefined(ot_version_long, data.ot_version_long);
    updateIfDefined(ruby_version, data.ruby_version);
    updateIfDefined(shrimp, data.shrimp);
  }

  function hydrateFeatureFlags(data: Partial<BootstrapPayload>): void {
    updateIfDefined(billing_enabled, data.billing_enabled);
    updateIfDefined(regions_enabled, data.regions_enabled);
    updateIfDefined(domains_enabled, data.domains_enabled);
    updateIfDefined(d9s_enabled, data.d9s_enabled);
    updateIfDefined(enjoyTheVue, data.enjoyTheVue);
  }

  function hydrateDomainConfig(data: Partial<BootstrapPayload>): void {
    updateIfDefined(canonical_domain, data.canonical_domain);
    updateIfDefined(domain_strategy, data.domain_strategy);
    updateIfDefined(domain_id, data.domain_id);
    updateIfDefined(display_domain, data.display_domain);
    updateIfDefined(domain_branding, data.domain_branding);
    updateIfDefined(domain_logo, data.domain_logo);
    updateIfDefined(domain_context, data.domain_context);
    updateIfDefined(custom_domains, data.custom_domains);
  }

  function hydrateSettings(data: Partial<BootstrapPayload>): void {
    updateIfDefined(regions, data.regions);
    updateIfDefined(available_jurisdictions, data.available_jurisdictions);
    updateIfDefined(authentication, data.authentication);
    updateIfDefined(secret_options, data.secret_options);
    updateIfDefined(diagnostics, data.diagnostics);
    updateIfDefined(ui, data.ui);
    updateIfDefined(features, data.features);
  }

  function hydrateDisplayAndMisc(data: Partial<BootstrapPayload>): void {
    updateIfDefined(messages, data.messages);
    updateIfDefined(homepage_mode, data.homepage_mode);
    updateIfDefined(global_banner, data.global_banner);
    updateIfDefined(development, data.development);
    updateIfDefined(stripe_customer, data.stripe_customer);
    updateIfDefined(stripe_subscriptions, data.stripe_subscriptions);
    updateIfDefined(entitlement_test_planid, data.entitlement_test_planid);
    updateIfDefined(entitlement_test_plan_name, data.entitlement_test_plan_name);
    updateIfDefined(organization, data.organization);
  }

  /**
   * Internal function to hydrate refs from a data snapshot.
   * Used by both init() and update().
   */
  function hydrateFromSnapshot(data: Partial<BootstrapPayload>): void {
    hydrateAuthState(data);
    hydrateUserIdentity(data);
    hydrateLocaleSettings(data);
    hydrateSiteConfig(data);
    hydrateFeatureFlags(data);
    hydrateDomainConfig(data);
    hydrateSettings(data);
    hydrateDisplayAndMisc(data);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET HELPERS - Split to reduce complexity
  // ═══════════════════════════════════════════════════════════════════════════

  function resetAuthState(): void {
    authenticated.value = DEFAULTS.authenticated;
    awaiting_mfa.value = DEFAULTS.awaiting_mfa;
    had_valid_session.value = DEFAULTS.had_valid_session;
  }

  function resetUserIdentity(): void {
    cust.value = DEFAULTS.cust;
    custid.value = DEFAULTS.custid;
    email.value = DEFAULTS.email;
    customer_since.value = DEFAULTS.customer_since;
    apitoken.value = DEFAULTS.apitoken;
  }

  function resetLocaleSettings(): void {
    i18n_enabled.value = DEFAULTS.i18n_enabled;
    locale.value = DEFAULTS.locale;
    supported_locales.value = DEFAULTS.supported_locales;
    fallback_locale.value = DEFAULTS.fallback_locale;
    default_locale.value = DEFAULTS.default_locale;
  }

  function resetSiteConfig(): void {
    baseuri.value = DEFAULTS.baseuri;
    frontend_host.value = DEFAULTS.frontend_host;
    site_host.value = DEFAULTS.site_host;
    ot_version.value = DEFAULTS.ot_version;
    ot_version_long.value = DEFAULTS.ot_version_long;
    ruby_version.value = DEFAULTS.ruby_version;
    shrimp.value = DEFAULTS.shrimp;
  }

  function resetFeatureFlags(): void {
    billing_enabled.value = DEFAULTS.billing_enabled;
    regions_enabled.value = DEFAULTS.regions_enabled;
    domains_enabled.value = DEFAULTS.domains_enabled;
    d9s_enabled.value = DEFAULTS.d9s_enabled;
    enjoyTheVue.value = DEFAULTS.enjoyTheVue;
  }

  function resetDomainConfig(): void {
    canonical_domain.value = DEFAULTS.canonical_domain;
    domain_strategy.value = DEFAULTS.domain_strategy;
    domain_id.value = DEFAULTS.domain_id;
    display_domain.value = DEFAULTS.display_domain;
    domain_branding.value = DEFAULTS.domain_branding;
    domain_logo.value = DEFAULTS.domain_logo;
    domain_context.value = (DEFAULTS.domain_context ?? null) as string | null;
    custom_domains.value = DEFAULTS.custom_domains;
  }

  function resetSettings(): void {
    regions.value = DEFAULTS.regions;
    available_jurisdictions.value = DEFAULTS.available_jurisdictions;
    authentication.value = DEFAULTS.authentication;
    secret_options.value = DEFAULTS.secret_options;
    diagnostics.value = DEFAULTS.diagnostics;
    ui.value = DEFAULTS.ui;
    features.value = DEFAULTS.features;
  }

  function resetDisplayAndMisc(): void {
    messages.value = DEFAULTS.messages;
    homepage_mode.value = DEFAULTS.homepage_mode;
    global_banner.value = DEFAULTS.global_banner;
    development.value = DEFAULTS.development;
    stripe_customer.value = DEFAULTS.stripe_customer;
    stripe_subscriptions.value = DEFAULTS.stripe_subscriptions;
    entitlement_test_planid.value = DEFAULTS.entitlement_test_planid;
    entitlement_test_plan_name.value = DEFAULTS.entitlement_test_plan_name;
    organization.value = DEFAULTS.organization;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /**
   * Initializes the store from bootstrap snapshot.
   * Called once during app initialization after Pinia is installed.
   *
   * @returns Object with initialization status
   */
  function init(): { isInitialized: boolean } {
    if (_initialized.value) {
      console.debug('[BootstrapStore.init] Already initialized, skipping');
      return { isInitialized: true };
    }

    const snapshot = getBootstrapSnapshot();

    if (!snapshot) {
      console.debug('[BootstrapStore.init] No bootstrap data available, using defaults');
      _initialized.value = true;
      return { isInitialized: true };
    }

    // Hydrate all refs from snapshot
    hydrateFromSnapshot(snapshot);

    _initialized.value = true;

    console.debug('[BootstrapStore.init] Initialized from snapshot:', {
      authenticated: authenticated.value,
      locale: locale.value,
      email: email.value,
    });

    return { isInitialized: true };
  }

  /**
   * Updates the store with new data from /bootstrap/me API response.
   * Only updates fields that are present in the data object.
   *
   * @param data - Partial BootstrapPayload data to merge
   */
  function update(data: Partial<BootstrapPayload>): void {
    hydrateFromSnapshot(data);

    console.debug('[BootstrapStore.update] Updated with:', {
      authenticated: data.authenticated,
      awaiting_mfa: data.awaiting_mfa,
      fieldsUpdated: Object.keys(data).length,
    });
  }

  /**
   * Resets the store to default values.
   * Called on logout to clear all user-specific state.
   */
  function $reset(): void {
    resetAuthState();
    resetUserIdentity();
    resetLocaleSettings();
    resetSiteConfig();
    resetFeatureFlags();
    resetDomainConfig();
    resetSettings();
    resetDisplayAndMisc();

    // Note: We keep _initialized true because the store structure is still valid
    // We just reset the data to defaults

    console.debug('[BootstrapStore.$reset] Reset to defaults');
  }

  /**
   * Refreshes state from the /bootstrap/me API endpoint.
   * Use this to sync state with the server after actions that change server state.
   *
   * @returns Promise that resolves when state is refreshed
   * @throws Error if fetch fails
   */
  async function refresh(): Promise<void> {
    if (typeof window === 'undefined') {
      throw new Error('[BootstrapStore] Cannot refresh: window is not defined');
    }

    const response = await fetch('/bootstrap/me', {
      method: 'GET',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`[BootstrapStore] Failed to refresh state: ${response.status}`);
    }

    const newState = (await response.json()) as BootstrapPayload;
    update(newState);
  }

  return {
    // State - Authentication
    authenticated,
    awaiting_mfa,
    had_valid_session,

    // State - User identity
    cust,
    custid,
    email,
    customer_since,
    apitoken,

    // State - Locale
    i18n_enabled,
    locale,
    supported_locales,
    fallback_locale,
    default_locale,

    // State - Site configuration
    baseuri,
    frontend_host,
    site_host,
    ot_version,
    ot_version_long,
    ruby_version,
    shrimp,

    // State - Feature flags
    billing_enabled,
    regions_enabled,
    domains_enabled,
    d9s_enabled,
    enjoyTheVue,

    // State - Domain
    canonical_domain,
    domain_strategy,
    domain_id,
    display_domain,
    domain_branding,
    domain_logo,
    domain_context,
    custom_domains,

    // State - Regions
    regions,
    available_jurisdictions,

    // State - Settings
    authentication,
    secret_options,
    diagnostics,
    ui,
    features,

    // State - Messages and display
    messages,
    homepage_mode,
    global_banner,

    // State - Development
    development,

    // State - Billing
    stripe_customer,
    stripe_subscriptions,

    // State - Colonel
    entitlement_test_planid,
    entitlement_test_plan_name,

    // State - Organization
    organization,

    // Getters
    isInitialized,
    headerConfig,
    footerLinksConfig,

    // Actions
    init,
    update,
    refresh,
    $reset,
  };
});
