<!-- src/shared/components/layout/MastHead.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DefaultLogo from '@/shared/components/logos/DefaultLogo.vue';
  import UserMenu from '@/shared/components/navigation/UserMenu.vue';
  import { useHeaderEnabled } from '@/shared/composables/useHeaderEnabled';
  import { DEFAULT_LOGO_COMPONENT } from '@/shared/constants/brand';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';
  import { computed, watch, type Component, onMounted, shallowRef } from 'vue';

  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const {
    authentication,
    awaiting_mfa,
    email,
    cust,
    ui,
  } = storeToRefs(bootstrapStore);

  // Brand identity resolves through the central resolver so the masthead shares
  // one neutral-safe source of truth with every other surface — the header reads
  // no raw brand/identity bootstrap fields directly. `productName` replaces the
  // hand-rolled `brand_product_name ?? NEUTRAL` snippet; `showPlatformIdentity`
  // is the base "may we show the platform wordmark?" decision (custom domains /
  // per-tenant logos suppress it — the A3 leak); `logoSource` supplies the
  // logo image on the identity axis: tenant logo, else the operator's
  // install-wide brand.logo_url (BRAND_LOGO_URL, suppressed on custom
  // domains), else the neutral DefaultLogo sentinel (#3612 — the operator
  // logo no longer comes from ui.header.branding).
  const identityStore = useProductIdentity();
  const {
    productName,
    displayName,
    showPlatformIdentity,
    installLogoUri,
    installLogoAlt,
    logoSource,
  } = storeToRefs(identityStore);

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  const isColonel = computed(() => cust.value?.role === 'colonel');

  // User is partially or fully authenticated - use centralized auth store getter
  // Partially: email verified but awaiting MFA (awaiting_mfa = true, has email but no cust)
  // Fully: all authentication steps complete (authenticated = true, has cust)
  const isUserPresent = computed(() => authStore.isUserPresent);

  // i18n setup
  const { t } = useI18n();

  // Header configuration
  const headerConfig = computed(() => ui.value?.header);

  // Default logo component for fallback (shared sentinel, also used by the
  // resolver's logoSource so the dynamic-import comparisons below stay in sync).
  const DEFAULT_LOGO = DEFAULT_LOGO_COMPONENT;

  // Helper functions for logo configuration.
  // Priority: props.logo.url (caller) > identity.logoSource, which itself
  // resolves tenant logo > operator brand.logo_url (BRAND_LOGO_URL, custom
  // domains excepted) > neutral DefaultLogo terminal. The masthead no longer
  // holds an operator-logo rung of its own — config authority lives in the
  // brand: block and resolution in the identity resolver (#3612).
  const getLogoUrl = () => props.logo?.url || logoSource.value;
  // Alt text: caller > operator BRAND_LOGO_ALT (only while the install logo
  // is the asset being shown) > i18n string derived from the product name.
  // When platform identity is suppressed (custom domain / tenant logo), the
  // accessible name must not leak the operator's product name either — use
  // the tenant-facing displayName (brand description or display domain),
  // mirroring what BrandedMastHead does for the same surface.
  const getLogoAlt = () =>
    props.logo?.alt ||
    installLogoAlt.value ||
    (showPlatformIdentity.value
      ? t('web.homepage.one_time_secret_literal', { product_name: productName.value })
      : displayName.value);
  const getLogoHref = () => props.logo?.href || headerConfig.value?.logo?.href || '/';

  // Custom install-wide logo: operator set BRAND_LOGO_URL. Distinct from the
  // tenant logo (identity.logoUri), because the two have different override
  // semantics for the site name. Sentinel comparison is gone: component
  // sentinels can never enter brand.logo_url (Config#normalize_brand rejects
  // them), so presence alone means "operator customized the logo".
  const isCustomStaticLogo = computed(() => !!installLogoUri.value);

  // LOGO_PROMINENT opt-in for larger logo sizing.
  const isProminentLogo = computed(() =>
    headerConfig.value?.logo?.prominent === true
  );

  // Logo sizing: LOGO_PROMINENT controls size, auth state determines the tier.
  // Default (prominent=false): 48px unauthenticated, 40px authenticated
  // Prominent (prominent=true): 160px unauthenticated, 80px authenticated
  const getLogoSize = () => {
    if (props.logo?.size) return props.logo.size;
    if (isProminentLogo.value) return isUserPresent.value ? 80 : 160;
    return isUserPresent.value ? 40 : 48;
  };
  // Priority:
  //   1. props.logo.showSiteName            (caller-site override)
  //   2. !identity.showPlatformIdentity     (resolver base guard: a per-tenant
  //                                          logo or any custom domain suppresses
  //                                          the platform wordmark — the A3 leak)
  //   3. headerConfig.logo.show_name        (LOGO_SHOW_NAME explicit layout knob;
  //                                          unset ships as null so the heuristic
  //                                          below can act)
  //   4. isCustomStaticLogo.value           (heuristic: a custom BRAND_LOGO_URL
  //                                          usually embeds its own wordmark)
  //   5. true                               (default: show the resolver-supplied
  //                                          product name next to the neutral mark)
  const getShowSiteName = () => {
    if (props.logo?.showSiteName != null) return props.logo.showSiteName;
    if (!showPlatformIdentity.value) return false;

    const showName = headerConfig.value?.logo?.show_name;
    if (showName != null) return showName;

    return !isCustomStaticLogo.value;
  };
  // The wordmark text is the resolver's productName (brand.product_name or
  // the neutral default) — the deprecated header.branding.site_name is
  // absorbed into brand.product_name by Config#normalize_brand (#3612).
  const getSiteName = () => props.logo?.siteName || t('web.homepage.one_time_secret_literal', { product_name: productName.value });
  const getAriaLabel = () => props.logo?.ariaLabel;
  const getIsColonelArea = () => props.logo?.isColonelArea ?? props.colonel;

  // Helper function to get logo configuration
  const getLogoConfig = () => ({
    url: getLogoUrl(),
    alt: getLogoAlt(),
    href: getLogoHref(),
    size: getLogoSize(),
    showSiteName: getShowSiteName(),
    siteName: getSiteName(),
    ariaLabel: getAriaLabel(),
    isColonelArea: getIsColonelArea(),
  });

  // Simplified logo configuration with prop override support
  const logoConfig = computed(getLogoConfig);

  // When a caller passes an explicit pixel size via props.logo.size, we must NOT
  // apply a Tailwind h-* class (the class would override the pixel value). In that
  // case we render the height via an inline style and skip the responsive class.
  const hasExplicitImgSize = computed(() => typeof props.logo?.size === 'number' && props.logo.size > 0);

  // Tailwind height classes mirror getLogoSize() logic.
  // Prominent: h-20 (80px) authenticated, h-24/sm:h-40 (96px mobile, 160px desktop) unauthenticated
  // Default: h-10 (40px) authenticated, h-12 (48px) unauthenticated
  const imgHeightClass = computed(() => {
    if (hasExplicitImgSize.value) return null;
    if (isProminentLogo.value) return isUserPresent.value ? 'h-20' : 'h-24 sm:h-40';
    return isUserPresent.value ? 'h-10' : 'h-12';
  });

  const imgInlineStyle = computed(() =>
    hasExplicitImgSize.value ? { height: `${props.logo!.size}px` } : undefined
  );

  // Operator-level header/navigation gates (HEADER_ENABLED), shared with the
  // header wrappers via the composable. Local headerConfig above stays for
  // branding/logo resolution.
  const { headerEnabled, navigationEnabled } = useHeaderEnabled();

  // Logo component handling
  const isVueComponent = computed(() => logoConfig.value.url.endsWith('.vue'));
  const logoComponent = shallowRef<Component | null>(
    isVueComponent.value && logoConfig.value.url === DEFAULT_LOGO
      ? DefaultLogo
      : null
  );

  // Helper function to load logo component
  const loadLogoComponent = async (logoUrl: string) => {
    if (!logoUrl.endsWith('.vue')) {
      logoComponent.value = null;
      return;
    }

    const componentName = logoUrl.replace('.vue', '');
    try {
      const module = await import(`@/shared/components/logos/${componentName}.vue`);
      logoComponent.value = module.default;
    } catch (error) {
      console.warn(`Failed to load logo component: ${logoUrl}`, error);
      await loadDefaultLogo(logoUrl);
    }
  };

  // Helper function to load default logo as fallback
  const loadDefaultLogo = async (originalUrl: string) => {
    if (originalUrl === DEFAULT_LOGO) {
      logoComponent.value = null;
      return;
    }

    try {
      const defaultComponent = DEFAULT_LOGO.replace('.vue', '');
      const module = await import(`@/shared/components/logos/${defaultComponent}.vue`);
      logoComponent.value = module.default;
      console.info(`Loaded fallback logo: ${defaultComponent}`);
    } catch (fallbackError) {
      console.error(`Failed to load fallback logo: ${DEFAULT_LOGO}`, fallbackError);
      logoComponent.value = null;
    }
  };

  // Watch for changes to logoUrl and load Vue component if needed
  watch(() => logoConfig.value.url, loadLogoComponent, { immediate: true });

  // Refresh bootstrap state to ensure auth status is up to date
  onMounted(async () => {
    try {
      await bootstrapStore.refresh();
    } catch (error) {
      console.warn('Failed to refresh bootstrap state:', error);
    }
  });

</script>

<template>
  <div v-if="headerEnabled" class="w-full">
    <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
      <!-- Logo lockup -->
      <div class="shrink-0">
        <div v-if="isVueComponent">
          <component
            id="logo"
            :is="logoComponent"
            v-if="logoComponent"
            v-bind="logoConfig"
            :is-user-present="isUserPresent"
            class="transition-transform" />
        </div>
        <div v-else>
          <a
            :href="logoConfig.href"
            data-testid="header-logo-link"
            class="flex items-center gap-3"
            :aria-label="logoConfig.alt">
            <img
              id="logo"
              :src="logoConfig.url"
              class="w-auto object-contain transition-transform"
              :class="imgHeightClass"
              :style="imgInlineStyle"
              :height="logoConfig.size"
              :alt="logoConfig.alt" />
            <span
              v-if="logoConfig.showSiteName"
              class="font-brand text-lg font-bold leading-tight">
              {{ logoConfig.siteName }}
            </span>
          </a>
        </div>
      </div>

      <!-- Context Switchers slot (collapses progressively: org text at lg+, domain text at md+) -->
      <div v-if="isUserPresent" class="flex min-w-0 flex-1 items-center gap-2 sm:gap-3">
        <slot name="context-switchers"></slot>
      </div>

      <!-- Navigation / User Menu -->
      <nav
        v-if="displayNavigation && navigationEnabled"
        role="navigation"
        :aria-label="t('web.layout.main_navigation')"
        class="ml-auto flex shrink-0 items-center justify-end gap-4
          font-brand text-sm sm:text-base">
        <template v-if="isUserPresent">
          <!-- User Menu Dropdown -->
          <UserMenu
            :cust="cust"
            :email="email"
            :colonel="isColonel"
            :awaiting-mfa="awaiting_mfa" />
        </template>

        <template v-else>
          <template v-if="authentication?.enabled">
            <!-- prettier-ignore-attribute class -->
            <router-link
              v-if="authentication?.signup"
              to="/signup"
              :title="t('web.homepage.signup_individual_and_business_plans')"
              class="font-bold text-gray-600 transition-colors duration-200
                hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
              data-testid="header-signup-cta">
              {{ t('web.COMMON.header_create_account') }}
            </router-link>
            <span
              v-if="authentication?.signup && authentication?.signin"
              class="text-gray-400"
              aria-hidden="true"
              role="separator">
              |
            </span>
            <!-- prettier-ignore-attribute class -->
            <router-link
              v-if="authentication?.signin"
              to="/signin"
              :title="t('web.homepage.log_in_to_onetime_secret', { product_name: productName })"
              data-testid="header-signin-link"
              class="text-gray-600 transition-colors duration-200
                hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ t('web.COMMON.header_sign_in') }}
            </router-link>
          </template>
        </template>
      </nav>
    </div>

  </div>
</template>
