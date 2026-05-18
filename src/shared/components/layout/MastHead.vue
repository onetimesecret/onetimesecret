<!-- src/shared/components/layout/MastHead.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DefaultLogo from '@/shared/components/logos/DefaultLogo.vue';
  import UserMenu from '@/shared/components/navigation/UserMenu.vue';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
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
    domain_logo,
  } = storeToRefs(bootstrapStore);

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

  // Default logo component for fallback
  const DEFAULT_LOGO = 'DefaultLogo.vue';

  // A URL counts as "custom branding" only when it's set AND differs from the
  // default Vue logo component (which the stock config always populates).
  const isCustomLogoUrl = (url: string | null | undefined): boolean =>
    !!url && url !== DEFAULT_LOGO;

  // Helper functions for logo configuration
  // Priority: props > custom domain logo > static config > default
  const getLogoUrl = () => props.logo?.url || domain_logo.value || headerConfig.value?.branding?.logo?.url || DEFAULT_LOGO;
  const getLogoAlt = () => props.logo?.alt || headerConfig.value?.branding?.logo?.alt || t('web.homepage.one_time_secret_literal');
  const getLogoHref = () => props.logo?.href || headerConfig.value?.branding?.logo?.link_to || '/';
  // Custom logos (props override, API domain branding, OR non-default static config)
  // are larger to emphasize brand identity. Excludes the default Vue logo so a stock
  // install doesn't enlarge the built-in icon.
  const isCustomLogo = computed(() =>
    isCustomLogoUrl(props.logo?.url)
    || !!domain_logo.value
    || isCustomLogoUrl(headerConfig.value?.branding?.logo?.url)
  );
  // Opt-in flag for operators who want custom logos to render larger in authenticated views.
  // Useful for rasterized brand assets that need visual presence alongside context switchers.
  const isProminentLogo = computed(() =>
    headerConfig.value?.branding?.logo?.prominent === true
  );
  // Authenticated users get a compact 40px logo by default so the org/domain context
  // switchers (rendered inline in the same flex row) have room and don't wrap below.
  // When prominent is enabled, authenticated users get an intermediate 80px size.
  // Unauthenticated users with a custom logo always get the prominent 160px treatment
  // for branded homepage / disabled views; unauthenticated default gets 48px.
  const getLogoSize = () => {
    if (props.logo?.size) return props.logo.size;
    if (isUserPresent.value) return isProminentLogo.value ? 80 : 40;
    if (isCustomLogo.value) return 160;
    return 48;
  };
  // Hide site name whenever a custom logo is in use; custom branding typically embeds
  // its own wordmark, so showing the site name alongside duplicates the brand identity.
  // Callers can opt back in via the props.logo.showSiteName override.
  // Priority: props > custom logo (any source, hide by default) > logo.show_name config > site_name presence
  const getShowSiteName = () => {
    if (props.logo?.showSiteName != null) return props.logo.showSiteName;
    if (isCustomLogo.value) return false;

    const showName = headerConfig.value?.branding?.logo?.show_name;
    return showName ?? !!headerConfig.value?.branding?.site_name;
  };
  const getSiteName = () => props.logo?.siteName || headerConfig.value?.branding?.site_name || t('web.homepage.one_time_secret_literal');
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

  const imgHeightClass = computed(() => {
    if (hasExplicitImgSize.value) return null;
    // Authenticated: compact by default (h-10 = 40px), or intermediate when prominent (h-20 = 80px)
    if (isUserPresent.value) return isProminentLogo.value ? 'h-20' : 'h-10';
    // Unauthenticated custom logo: compact on mobile (h-24 = 96px), prominent from sm up (h-40 = 160px)
    if (isCustomLogo.value) return 'h-24 sm:h-40';
    return 'h-12';
  });

  const imgInlineStyle = computed(() =>
    hasExplicitImgSize.value ? { height: `${props.logo!.size}px` } : undefined
  );

  const navigationEnabled = computed(() =>
    headerConfig.value?.navigation?.enabled !== false
  );

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
  <div class="w-full">
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
              :title="t('web.homepage.log_in_to_onetime_secret')"
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
