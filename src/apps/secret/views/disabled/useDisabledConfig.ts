// src/apps/secret/views/disabled/useDisabledConfig.ts
//
// Derives all rendering inputs for the disabled-homepage variants from
// bootstrap + identity stores in one place, so the dispatcher can pass a
// single props bag to whichever variant is selected and the variants stay
// purely presentational.
//
// Variant comes from the per-domain `homepage_config.disabled_homepage_variant`
// (with a `?variant` URL override and a frontend-constant fallback). The
// affordance flags (show_promo / show_what_is_this) come from auto-detection
// rules plus operator overrides on the site-level `bootstrap.disabled_homepage`
// block.

import type { DisabledHomepageVariant } from '@/schemas/contracts/disabled-homepage';
import {
  DEFAULT_DISABLED_HOMEPAGE_VARIANT,
  disabledHomepageVariantSchema,
} from '@/schemas/contracts/disabled-homepage';
import type { Features } from '@/schemas/contracts/bootstrap';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useProductIdentity } from '@/shared/stores/identityStore';
import type { SsoProvider } from '@/utils/features';
import { submitSsoLogin } from '@/shared/utils/sso';
import { storeToRefs } from 'pinia';
import { computed, type ComputedRef } from 'vue';

/**
 * Read a one-off variant override from the current URL.
 *
 * Operator/dogfood escape hatch: `?variant=minimal` (or `v1` / `closed`)
 * wins over bootstrap config. Useful for previewing a variant before
 * flipping the deployment default, and for sanity-checking dispatch
 * when bootstrap is suspected of carrying a stale value.
 *
 * Invalid or missing values fall through silently.
 */
function readUrlVariantOverride(): DisabledHomepageVariant | null {
  if (typeof window === 'undefined') return null;
  const raw = new URLSearchParams(window.location.search).get('variant');
  if (!raw) return null;
  const parsed = disabledHomepageVariantSchema.safeParse(raw);
  return parsed.success ? parsed.data : null;
}

/**
 * Props bag shared by every disabled-homepage variant.
 *
 * Variants should treat these as the complete contract — anything they
 * need from app state should be added here, not read directly inside
 * variant components, so dispatch stays the single composition root.
 *
 * `whatIsThisHref` and `promoHref` are nullable: an empty `siteHost`
 * would produce `https:///`, which is useless. The dispatcher gates the
 * matching `show*` flag whenever the href is null, so variants can
 * assume the href is a real URL whenever the flag is true.
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
  /** Operator-configured URL for "What is this link?" — null when unset. */
  whatIsThisHref: string | null;
  /** Whether to render the free-tier promo strip. */
  showPromo: boolean;
  /** External href for the promo's "Learn how" link — null when unresolvable. */
  promoHref: string | null;
  /**
   * Whether the sign-in CTA should initiate SSO directly instead of routing
   * to /signin. True only when SSO is the sole login method and exactly one
   * provider is configured, so the extra /signin hop adds nothing.
   */
  ssoOneClick: boolean;
  /** Display name of the single SSO provider, for the one-click CTA label. */
  ssoProviderName: string | null;
  /** Initiates one-click SSO login (POST to /auth/sso/:provider). */
  onSsoLogin: () => void;
}

interface DisabledHomepageBindings {
  /** Reactive variant id — re-reads bootstrap on every access so a config
   *  refresh (re-hydration / login / logout) flips the rendered variant. */
  variant: ComputedRef<DisabledHomepageVariant>;
  /** Reactive props bag. Each property is a getter so `v-bind="props"`
   *  re-reads on every render, preserving reactivity through the spread. */
  props: DisabledHomepageProps;
}

/**
 * Resolve a tri-state override: explicit operator setting wins, null falls
 * through to the auto-detection rule.
 */
function applyOverride(override: boolean | null | undefined, auto: boolean): boolean {
  return override === null || override === undefined ? auto : override;
}

/**
 * The single SSO provider to one-click into from the disabled-homepage CTA, or
 * null when the CTA should fall back to the standard /signin link.
 *
 * Returns a provider only when SSO is the sole login method — mirroring
 * AuthMethodSelector: global `restrict_to === 'sso'`, or a custom domain with
 * `enforce_sso_only` — *and* exactly one provider is configured. With multiple
 * providers, /signin still has to present a chooser, so the hop earns its keep
 * and we don't short-circuit it.
 */
function resolveSsoOneClickProvider(
  features: Features | undefined,
  isCustom: boolean
): SsoProvider | null {
  const sso = features?.sso;
  const providers =
    sso && typeof sso !== 'boolean' && sso.enabled && Array.isArray(sso.providers)
      ? sso.providers
      : [];
  if (providers.length !== 1) return null;

  const restrictedToSso = features?.restrict_to === 'sso';
  const enforcedForDomain =
    typeof sso === 'object' && sso !== null ? sso.enforce_sso_only === true : false;
  return restrictedToSso || (isCustom && enforcedForDomain) ? providers[0] : null;
}

/**
 * Validate a resolved variant id against the enum, collapsing every invalid
 * case (null, undefined, empty string, unknown/legacy id) to the default.
 *
 * `??` in the resolution chain only skips null/undefined, so an empty-string or
 * unrecognised store value would otherwise reach the dispatcher's
 * `VARIANTS[variant]` as an unknown key -> `<component :is=undefined>` -> a
 * blank page. This guard prevents that.
 */
function coerceDisabledVariant(candidate: unknown): DisabledHomepageVariant {
  const parsed = disabledHomepageVariantSchema.safeParse(candidate);
  return parsed.success ? parsed.data : DEFAULT_DISABLED_HOMEPAGE_VARIANT;
}

export function useDisabledConfig(): DisabledHomepageBindings {
  const identityStore = useProductIdentity();
  const { isCustom, primaryColor, logoUri, displayName, displayDomain, brand, siteHost } =
    storeToRefs(identityStore);

  const bootstrapStore = useBootstrapStore();
  const { authentication, billing_enabled, disabled_homepage, features, homepage_config, ui } =
    storeToRefs(bootstrapStore);

  const csrfStore = useCsrfStore();

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

  // The "What is this link?" affordance points at an operator-configured
  // URL (site.interface.ui.homepage.public_links.recipient_intro). When
  // unset, the affordance is hidden — no broken-link fallback.
  const whatIsThisHref = computed(
    () => ui.value?.homepage?.public_links?.recipient_intro?.trim() || null
  );

  // Promo "Learn how" still derives from siteHost since it points at the
  // canonical pricing page, not at operator-controlled content.
  const hasSiteHost = computed(() => !!siteHost.value);
  const promoHref = computed(() =>
    hasSiteHost.value ? `https://${siteHost.value}/pricing` : null
  );

  // Auto-detection: show "What is this link?" when the operator has
  // configured a destination URL. Override can still force it off.
  const showWhatIsThisAuto = computed(() => !!whatIsThisHref.value);
  const showWhatIsThis = computed(
    () =>
      !!whatIsThisHref.value &&
      applyOverride(disabled_homepage.value?.show_what_is_this, showWhatIsThisAuto.value)
  );

  // Auto-detection: the "free plans now include custom domains" promo is
  // SaaS-specific marketing aimed at visitors to free-tier custom domains.
  // Self-hosted (billing_enabled=false), canonical site, and branded domains
  // all suppress it. Operator override wins, but again we suppress when the
  // href is unresolvable.
  const showPromoAuto = computed(
    () => !isBranded.value && isCustom.value && billing_enabled.value && hasSiteHost.value
  );
  const showPromo = computed(
    () =>
      hasSiteHost.value &&
      applyOverride(disabled_homepage.value?.show_promo, showPromoAuto.value)
  );

  const showSignin = computed(() => !!authentication.value?.signin);

  // One-click SSO: when SSO is the only sign-in method and a single provider
  // is configured, the CTA POSTs straight to the IdP instead of routing to
  // /signin (itself just a lone "Sign in with <provider>" button in that
  // configuration). See resolveSsoOneClickProvider for the gating.
  const ssoProvider = computed(() => resolveSsoOneClickProvider(features.value, isCustom.value));
  const ssoOneClick = computed(() => showSignin.value && ssoProvider.value !== null);

  const onSsoLogin = () => {
    const provider = ssoProvider.value;
    if (!provider) return;
    submitSsoLogin({ routeName: provider.route_name, shrimp: csrfStore.shrimp });
  };

  // Variant resolution (highest precedence first):
  //   1. ?variant= URL override (dogfood/preview)
  //   2. per-domain homepage_config.disabled_homepage_variant
  //   3. deployment-wide ui.homepage.disabled_variant
  //      (DEFAULT_DISABLED_HOMEPAGE_VARIANT env var)
  //   4. frontend DEFAULT_DISABLED_HOMEPAGE_VARIANT constant
  // URL is read once at composable-call time (page loads don't preserve query
  // params); the store-backed fallbacks stay reactive so a $patch on the
  // domain or site config still flips the variant. homepage_config is null on
  // the canonical site and on any custom domain that hasn't opted in.
  const urlOverride = readUrlVariantOverride();
  // Wrap the ?? precedence chain in coerceDisabledVariant so an invalid/empty
  // store value falls back to the default instead of blanking the dispatcher.
  const variant = computed<DisabledHomepageVariant>(() =>
    coerceDisabledVariant(
      urlOverride ??
        homepage_config.value?.disabled_homepage_variant ??
        ui.value?.homepage?.disabled_variant
    )
  );

  // Getter object: `v-bind="props"` evaluates each property on every render,
  // so each getter re-reads its source computed and reactivity is preserved
  // through the spread. Plain destructuring would freeze values at call time.
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
    get ssoOneClick() { return ssoOneClick.value; },
    get ssoProviderName() { return ssoProvider.value?.display_name ?? null; },
    onSsoLogin,
  } satisfies DisabledHomepageProps;

  return { variant, props };
}
