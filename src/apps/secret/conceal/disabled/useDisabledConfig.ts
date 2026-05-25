// src/apps/secret/conceal/disabled/useDisabledConfig.ts
//
// Derives all rendering inputs for the disabled-homepage variants from
// bootstrap + identity stores in one place, so the dispatcher can pass a
// single props bag to whichever variant is selected and the variants stay
// purely presentational.
//
// The composable applies auto-detection rules by default and lets operator
// overrides (bootstrap.disabled_homepage) win when set.

import type { DisabledHomepageVariant } from '@/schemas/contracts/disabled-homepage';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

/**
 * Props bag shared by every disabled-homepage variant.
 *
 * Variants should treat these as the complete contract — anything they
 * need from app state should be added here, not read directly inside
 * variant components, so dispatch stays the single composition root.
 */
export interface DisabledHomepageProps {
  /** Branded = custom domain with a configured brand description. */
  isBranded: boolean;
  /** Workspace display name for branded mode (e.g. "Acme"). */
  workspaceName: string;
  /** Single uppercase letter for the monogram fallback. */
  monogramInitial: string;
  /** Custom brand color (hex). Defaults to OTS orange when unbranded. */
  primaryColor: string;
  /** Tenant-uploaded logo URL; falls back to monogram when null. */
  logoUri: string | null;
  /** Domain the visitor sees in the URL bar. */
  displayDomain: string;
  /** Whether to render the "Sign in" CTA (auth.signin must be enabled). */
  showSignin: boolean;
  /** Whether to render the "What is this?" link. */
  showWhatIsThis: boolean;
  /** External href for "What is this?" (canonical site for this deployment). */
  whatIsThisHref: string;
  /** Whether to render the free-tier promo strip. */
  showPromo: boolean;
  /** External href for the promo's "Learn how" link. */
  promoHref: string;
}

interface DisabledHomepageBindings {
  variant: DisabledHomepageVariant;
  props: DisabledHomepageProps;
}

/**
 * Resolve a tri-state override: explicit operator setting wins, null falls
 * through to the auto-detection rule.
 */
function applyOverride(override: boolean | null | undefined, auto: boolean): boolean {
  return override === null || override === undefined ? auto : override;
}

export function useDisabledConfig(): DisabledHomepageBindings {
  const identityStore = useProductIdentity();
  const { isCustom, primaryColor, logoUri, displayName, displayDomain, brand, siteHost } =
    storeToRefs(identityStore);

  const bootstrapStore = useBootstrapStore();
  const { authentication, billing_enabled, disabled_homepage } = storeToRefs(bootstrapStore);

  // "Branded" means a custom domain has actually been configured with a brand
  // description — distinct from isCustom, which can be true even when no
  // branding is set (free tier with a custom domain).
  const isBranded = computed(() => isCustom.value && !!brand.value?.description);

  const workspaceName = computed(
    () => brand.value?.description?.trim() || displayName.value
  );

  const monogramInitial = computed(() =>
    (workspaceName.value || displayDomain.value || 'A').trim().charAt(0).toUpperCase()
  );

  // Auto-detection: "What is this?" makes sense only on a custom domain
  // (canonical visitors are already at "the source"). Operator override wins.
  const showWhatIsThisAuto = computed(() => isCustom.value && !!siteHost.value);
  const showWhatIsThis = computed(() =>
    applyOverride(disabled_homepage.value?.show_what_is_this, showWhatIsThisAuto.value)
  );

  // Auto-detection: the "free plans now include custom domains" promo is
  // SaaS-specific marketing aimed at visitors to free-tier custom domains.
  // Self-hosted (billing_enabled=false), canonical site, and branded domains
  // all suppress it. Operator override wins.
  const showPromoAuto = computed(
    () => !isBranded.value && isCustom.value && billing_enabled.value
  );
  const showPromo = computed(() =>
    applyOverride(disabled_homepage.value?.show_promo, showPromoAuto.value)
  );

  const showSignin = computed(() => !!authentication.value?.signin);

  const whatIsThisHref = computed(() => `https://${siteHost.value}/`);
  const promoHref = computed(() => `https://${siteHost.value}/pricing`);

  // Pinia refs are unwrapped on read in the consuming template, but the
  // returned object freezes a snapshot of refs at call time. Wrap reactive
  // reads in a getter object so the dispatcher's template re-renders as
  // store values change.
  const props = {
    get isBranded() { return isBranded.value; },
    get workspaceName() { return workspaceName.value; },
    get monogramInitial() { return monogramInitial.value; },
    get primaryColor() { return primaryColor.value; },
    get logoUri() { return logoUri.value; },
    get displayDomain() { return displayDomain.value; },
    get showSignin() { return showSignin.value; },
    get showWhatIsThis() { return showWhatIsThis.value; },
    get whatIsThisHref() { return whatIsThisHref.value; },
    get showPromo() { return showPromo.value; },
    get promoHref() { return promoHref.value; },
  } as DisabledHomepageProps;

  return {
    variant: disabled_homepage.value?.variant ?? 'v1',
    props,
  };
}
