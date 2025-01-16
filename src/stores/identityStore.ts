// stores/productIdentity.ts
import { brandSettingschema, type BrandSettings } from '@/schemas/models/domain/brand';
import { WindowService } from '@/services/window.service';
import { defineStore } from 'pinia';
import { computed, reactive, toRefs } from 'vue';
import { useI18n } from 'vue-i18n';

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
  allowPublicHomepage: boolean;
}

/**
 * Zod validator for primary color field
 * Ensures color values conform to brand schema requirements
 */
const primaryColorValidator = brandSettingschema.shape.primary_color;
const allowPublicHomepageValidator = brandSettingschema.shape.allow_public_homepage;

/**
 * Creates initial identity state from window service values
 * Handles validation and default values for branding fields
 */
const getInitialState = (): IdentityState => {
  const domainStrategy = WindowService.get('domain_strategy');
  const brand = WindowService.get('domain_branding');
  const defaultPrimaryColor = primaryColorValidator.parse(undefined);
  return {
    domainStrategy,
    domainsEnabled: WindowService.get('domains_enabled'),
    displayDomain: WindowService.get('display_domain'),
    siteHost: WindowService.get('site_host'),
    canonicalDomain: WindowService.get('canonical_domain'),
    domainId: WindowService.get('domain_id'),
    brand,
    primaryColor:
      domainStrategy === 'custom' && brand?.primary_color
        ? primaryColorValidator.parse(brand.primary_color)
        : defaultPrimaryColor,
    allowPublicHomepage: allowPublicHomepageValidator.parse(brand?.allow_public_homepage),
  };
};

/**
 * Manages product identity state including domain context and branding
 * Identity determines how the product is presented and behaves for the current domain
 */
/* eslint-disable max-lines-per-function */
export const useProductIdentity = defineStore('productIdentity', () => {
  // Get i18n instance via injection
  const { t } = useI18n();

  const state = reactive<IdentityState>(getInitialState());

  /** Whether serving from primary domain */
  const isCanonical = computed(() => state.domainStrategy === 'canonical');

  /** Whether serving from custom domain */
  const isCustom = computed(() => state.domainStrategy === 'custom');

  /** Whether serving from subdomain */
  const isSubdomain = computed(() => state.domainStrategy === 'subdomain');

  /** Display name for current domain context */
  const displayName = computed(() => state.brand?.description || state.displayDomain);

  const logoUri = computed(() => {
    const template = '/imagine/:custom_domain_id/:image_type.:image_ext';
    return template
      .replace(':custom_domain_id', state.domainId)
      .replace(':image_type', 'logo')
      .replace(':image_ext', 'png');
  });

  const cornerClass = computed(() => {
    switch (state.brand?.corner_style) {
      case 'rounded':
        return 'rounded-md'; // Updated to match BaseSecretDisplay
      case 'pill':
        return 'rounded-xl'; // Updated to match BaseSecretDisplay
      case 'square':
        return 'rounded-none';
      default:
        return '';
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
    () =>
      state.brand?.instructions_pre_reveal?.trim() || t('web.shared.pre_reveal_default')
  );

  const postRevealInstructions = computed(
    () =>
      state.brand?.instructions_post_reveal?.trim() || t('web.shared.post_reveal_default')
  );

  /** Resets state to initial values from window service */
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

    ...toRefs(state), //
  };
});
