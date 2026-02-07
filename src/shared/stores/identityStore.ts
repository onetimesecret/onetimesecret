// src/shared/stores/identityStore.ts

import { brandSettingschema, type BrandSettings } from '@/schemas/models/domain/brand';
import { DEFAULT_BRAND_HEX } from '@/utils/brand-palette';
import { defineStore, storeToRefs } from 'pinia';
import { computed, reactive, toRefs, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBootstrapStore } from './bootstrapStore';

export const DEFAULT_PRIMARY_COLOR = DEFAULT_BRAND_HEX;
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
 * Zod validator extracted from the brand schema's primary_color field.
 * Used to validate (not default) the color value before entering the
 * fallback chain. Returns the validated hex string, or null/undefined
 * when the field is absent — which lets ?? fall through to the next
 * source in the chain.
 */
const primaryColorValidator = brandSettingschema.shape.primary_color;

/**
 * Manages product identity state including domain context and branding
 * Identity determines how the product is presented and behaves for the current domain
 */

// eslint-disable-next-line max-lines-per-function -- Store setup requires coordinating multiple reactive refs and watchers
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
  } = storeToRefs(bootstrapStore);

  /**
   * Creates initial identity state from bootstrapStore values
   * Handles validation and default values for branding fields
   */
  function getInitialState(): IdentityState {
    const brand = brandSettingschema.parse(domain_branding.value ?? {});

    // 3-step fallback chain for primary color resolution:
    //   1. Per-domain color from Redis (custom domain branding)
    //   2. Per-installation color from config (branding.primary_color)
    //   3. Hardcoded default (#dc4a22)
    // This supports both multi-tenant (step 1 per domain, step 3
    // as shared default) and single-tenant elite (step 2 from ENV).
    // The brand schema uses .nullish() instead of .default() so that
    // absent domain colors fall through to steps 2 and 3.
    const primaryColor =
      primaryColorValidator.parse(brand.primary_color) ??
      bootstrapStore.brand_primary_color ??
      DEFAULT_PRIMARY_COLOR;
    const buttonTextLight = brand.button_text_light ?? DEFAULT_BUTTON_TEXT_LIGHT;
    const allowPublicHomepage = brand.allow_public_homepage ?? false;

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

  // Watch for domain branding changes — re-evaluate the fallback chain
  watch(domain_branding, (newBranding) => {
    const brand = brandSettingschema.parse(newBranding ?? {});
    state.brand = brand;
    state.primaryColor =
      primaryColorValidator.parse(brand.primary_color) ??
      bootstrapStore.brand_primary_color ??
      DEFAULT_PRIMARY_COLOR;
    state.buttonTextLight = brand.button_text_light ?? DEFAULT_BUTTON_TEXT_LIGHT;
    state.allowPublicHomepage = brand.allow_public_homepage ?? false;
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
    }
  );

  /** Whether serving from primary domain */
  const isCanonical = computed(() => state.domainStrategy === 'canonical');

  /** Whether serving from custom domain */
  const isCustom = computed(() => state.domainStrategy === 'custom');

  /** Whether serving from subdomain */
  const isSubdomain = computed(() => state.domainStrategy === 'subdomain');

  /** Display name for current domain context */
  const displayName = computed(() => state.brand?.description || state.displayDomain);

  /** Logo URL for custom domain, pre-computed by backend with correct extid */
  const logoUri = computed(() =>
    // Backend provides the correct logo URL using extid (external ID).
    // Returns null if no logo is uploaded for this custom domain.
    // Note: Client-side URL generation is not possible since we only have
    // the internal domainId, not the public extid needed for the /imagine route.
    domain_logo.value
  );

  const cornerClass = computed(() => {
    switch (state.brand?.corner_style) {
      case 'rounded':
        return 'rounded-md'; // Updated to match BaseSecretDisplay
      case 'pill':
        return 'rounded-xl'; // Updated to match BaseSecretDisplay
      case 'square':
        return 'rounded-none';
      default:
        return DEFAULT_CORNER_CLASS;
    }
  });

  const fontFamilyClass = computed(() => {
    switch (state.brand?.font_family) {
      case 'sans':
        return 'font-sans';
      case 'serif':
        return 'font-serif';
      case 'mono':
        return 'font-mono';
      default:
        return '';
    }
  });

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
    $reset,

    ...toRefs(state),
  };
});
