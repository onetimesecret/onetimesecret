// src/shared/stores/identityStore.ts

import {
  brandSettingsSchema,
  type BrandSettings,
} from '@/schemas/shapes/v3/custom-domain';
import { NEUTRAL_BRAND_DEFAULTS, resolveProductName } from '@/shared/constants/brand';
import { cornerStyleClasses, fontFamilyClasses } from '@/shared/utils/brand-helpers';
import { gracefulParse } from '@/utils/schemaValidation';
import { defineStore, storeToRefs } from 'pinia';
import { computed, reactive, toRefs, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBootstrapStore } from './bootstrapStore';

export const DEFAULT_CORNER_CLASS = 'rounded-lg';
export const DEFAULT_BUTTON_TEXT_LIGHT = true; // light text for default colour

/**
 * Represents the product's identity state for a given domain context
 */
interface IdentityState {
  /** Domain validation state from middleware: canonical, subdomain, custom, or invalid */
  domainStrategy: 'canonical' | 'subdomain' | 'custom' | 'invalid';
  /** Whether multiple domains are enabled in system configuration */
  domainsEnabled: boolean;
  /** Current domain being served */
  displayDomain: string;
  /** Site host for this application */
  siteHost: string;
  /** System's primary domain */
  canonicalDomain: string;
  /** Database ID of custom domain if applicable */
  domainId: string;
  /** Custom branding settings if applicable */
  brand: BrandSettings | null;
  /** Primary color for branding */
  primaryColor: string;
  buttonTextLight: boolean;
  allowPublicHomepage: boolean;
}

/**
 * Zod validator for primary color field
 * Ensures color values conform to brand schema requirements
 */
const primaryColorValidator = brandSettingsSchema.shape.primary_color;

/**
 * Manages product identity state including domain context and branding
 * Identity determines how the product is presented and behaves for the current domain
 */

// Store setup requires coordinating multiple reactive refs and watchers.
// eslint-disable-next-line max-lines-per-function
export const useProductIdentity = defineStore('productIdentity', () => {
  // Get i18n instance via injection
  const { t } = useI18n();

  // Access bootstrapStore for all domain/branding data
  const bootstrapStore = useBootstrapStore();
  const {
    domain_strategy,
    domains_enabled,
    display_domain,
    site_host,
    canonical_domain,
    domain_id,
    domain_branding,
    domain_logo,
    brand_product_name,
    homepage_config,
  } = storeToRefs(bootstrapStore);

  /**
   * Resolves the active primary color through a 3-step fallback chain:
   *   1. Per-domain branding (Redis custom domain settings)
   *   2. Install config (BRAND_PRIMARY_COLOR env var via bootstrapStore)
   *   3. Neutral last resort (NEUTRAL_BRAND_DEFAULTS.primary_color)
   *
   * Both steps 1 and 2 are validated through primaryColorValidator so
   * malformed values degrade gracefully instead of reaching the palette
   * generator.
   */
  function resolvePrimaryColor(brandColor: unknown): string {
    const domainParsed = gracefulParse(primaryColorValidator, brandColor, 'PrimaryColor');
    const domainValidated = domainParsed.ok ? domainParsed.data : null;

    const installParsed = gracefulParse(primaryColorValidator, bootstrapStore.brand_primary_color, 'InstallPrimaryColor');
    const installValidated = installParsed.ok ? installParsed.data : null;

    return (
      domainValidated ??
      installValidated ??
      NEUTRAL_BRAND_DEFAULTS.primary_color
    );
  }

  /**
   * Creates initial identity state from bootstrapStore values
   * Handles validation and default values for branding fields
   */
  function getInitialState(): IdentityState {
    const brandResult = gracefulParse(brandSettingsSchema, domain_branding.value ?? {}, 'BrandSettings');
    const brand = brandResult.ok ? brandResult.data : null;

    const primaryColor = resolvePrimaryColor(brand?.primary_color);
    const buttonTextLight = brand?.button_text_light ?? DEFAULT_BUTTON_TEXT_LIGHT;
    const allowPublicHomepage = homepage_config.value?.enabled ?? false;

    return {
      domainStrategy: domain_strategy.value,
      domainsEnabled: domains_enabled.value,
      displayDomain: display_domain.value,
      siteHost: site_host.value,
      canonicalDomain: canonical_domain.value,
      domainId: domain_id.value,
      brand,
      primaryColor,
      buttonTextLight,
      allowPublicHomepage,
    };
  }

  const state = reactive<IdentityState>(getInitialState());

  // Watch for domain branding changes to update derived state
  watch(domain_branding, (newBranding) => {
    const brandResult = gracefulParse(brandSettingsSchema, newBranding ?? {}, 'BrandSettings');
    const brand = brandResult.ok ? brandResult.data : null;
    state.brand = brand;

    state.primaryColor = resolvePrimaryColor(brand?.primary_color);
    state.buttonTextLight = brand?.button_text_light ?? DEFAULT_BUTTON_TEXT_LIGHT;
  });

  // Watch for install-config color changes (e.g. /bootstrap/me refresh)
  watch(
    () => bootstrapStore.brand_primary_color,
    () => {
      state.primaryColor = resolvePrimaryColor(state.brand?.primary_color);
    }
  );

  // Watch homepage_config for toggle state (authoritative source, separate from brand)
  watch(homepage_config, (newConfig) => {
    state.allowPublicHomepage = newConfig?.enabled ?? false;
  });

  // Watch for domain config changes (consolidated for reduced reactive overhead)
  watch(
    [domain_strategy, domains_enabled, display_domain, site_host, canonical_domain, domain_id],
    ([strategy, enabled, display, host, canonical, id]) => {
      state.domainStrategy = strategy;
      state.domainsEnabled = enabled;
      state.displayDomain = display;
      state.siteHost = host;
      state.canonicalDomain = canonical;
      state.domainId = id;
    },
    { immediate: true }
  );

  /** Whether serving from primary domain */
  const isCanonical = computed(() => state.domainStrategy === 'canonical');

  /** Whether serving from custom domain */
  const isCustom = computed(() => state.domainStrategy === 'custom');

  /** Whether serving from subdomain */
  const isSubdomain = computed(() => state.domainStrategy === 'subdomain');

  /** Display name for current domain context */
  const displayName = computed(() => state.brand?.description || state.displayDomain);

  /**
   * Install product name, neutral-safe. Never the hardcoded OTS literal.
   *
   * Centralizes the `brand_product_name || NEUTRAL_BRAND_DEFAULTS.product_name`
   * fallback that surfaces (MastHead, DefaultLogo) previously each re-derived by
   * hand — so a new name-rendering surface has one safe source of truth instead
   * of another chance to leak "Onetime Secret". Shares `resolveProductName` with
   * `usePageTitle`, which cannot depend on this store (it runs in router guards,
   * outside the i18n context this store initializes with).
   */
  const productName = computed(() => resolveProductName(brand_product_name?.value));

  /** Logo URL for custom domain, pre-computed by backend with correct extid */
  const logoUri = computed(() =>
    // Backend provides the correct logo URL using extid (external ID).
    // Returns null if no logo is uploaded for this custom domain.
    // Note: Client-side URL generation is not possible since we only have
    // the internal domainId, not the public extid needed for the /imagine route.
    domain_logo.value
  );

  /**
   * Whether a surface may show the platform's own name / wordmark.
   *
   * False on a custom domain — with or without an uploaded logo — and whenever a
   * per-tenant logo is present: rendering the install's identity there would
   * leak it onto another company's domain (the A3 masthead leak). Canonical and
   * subdomain contexts are permitted to show it, subject to the consumer's own
   * config (a `subdomain` IS the platform, so its name legitimately shows).
   *
   * This encodes only the base identity-leak guard; consumers keep their own
   * override ladder (caller props, operator LOGO_SHOW_NAME, etc.) on top.
   */
  const showPlatformIdentity = computed(() => !isCustom.value && !logoUri.value);

  const cornerClass = computed(() =>
    state.brand?.corner_style
      ? cornerStyleClasses[state.brand.corner_style] ?? DEFAULT_CORNER_CLASS
      : DEFAULT_CORNER_CLASS
  );

  const fontFamilyClass = computed(() =>
    state.brand?.font_family
      ? fontFamilyClasses[state.brand.font_family] ?? ''
      : ''
  );

  const preRevealInstructions = computed(
    () => state.brand?.instructions_pre_reveal?.trim() || t('web.shared.pre_reveal_default')
  );

  const postRevealInstructions = computed(
    () => state.brand?.instructions_post_reveal?.trim() || t('web.shared.post_reveal_default')
  );

  /** Resets state to initial values from bootstrapStore */
  function $reset() {
    // Maintains reactivity by modifying the existing properties
    Object.assign(state, getInitialState());
  }

  return {
    logoUri,
    cornerClass,
    fontFamilyClass,
    preRevealInstructions,
    postRevealInstructions,

    isCanonical,
    isCustom,
    isSubdomain,
    displayName,
    productName,
    showPlatformIdentity,
    $reset,

    ...toRefs(state),
  };
});
