<!-- src/shared/components/layout/MastHead.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DefaultLogo from '@/shared/components/logos/DefaultLogo.vue';
  import UserMenu from '@/shared/components/navigation/UserMenu.vue';
  import { WindowService } from '@/services/window.service';
  import { useAuthStore } from '@/shared/stores/authStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, watch, type Component, onMounted } from 'vue';
  import { shallowRef } from 'vue';

  const authStore = useAuthStore();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  // Make window properties reactive by using computed
  const windowProps = computed(() => WindowService.getMultiple([
    'authentication',
    'authenticated',
    'awaiting_mfa',
    'email',
    'cust',
    'ui',
    'domain_logo',
  ]));

  const isColonel = computed(() => windowProps.value.cust?.role === 'colonel');

  // User is partially or fully authenticated - use centralized auth store getter
  // Partially: email verified but awaiting MFA (awaiting_mfa = true, has email but no cust)
  // Fully: all authentication steps complete (authenticated = true, has cust)
  const isUserPresent = computed(() => authStore.isUserPresent);

  // i18n setup
  const { t } = useI18n();

  // Header configuration
  const headerConfig = computed(() => windowProps.value.ui?.header);

  // Default logo component for fallback
  const DEFAULT_LOGO = 'DefaultLogo.vue';

  // Helper functions for logo configuration
  // Priority: props > custom domain logo > static config > default
  const getLogoUrl = () => props.logo?.url || windowProps.value.domain_logo || headerConfig.value?.branding?.logo?.url || DEFAULT_LOGO;
  const getLogoAlt = () => props.logo?.alt || headerConfig.value?.branding?.logo?.alt || t('web.homepage.one_time_secret_literal');
  const getLogoHref = () => props.logo?.href || headerConfig.value?.branding?.logo?.link_to || '/';
  // Custom domain logos are larger to emphasize brand identity
  const isCustomDomainLogo = computed(() => !!windowProps.value.domain_logo);
  const getLogoSize = () => props.logo?.size || (isCustomDomainLogo.value ? 80 : 64);
  // Hide site name when custom domain logo is displayed (unless explicitly configured)
  const getShowSiteName = () => props.logo?.showSiteName ?? (windowProps.value.domain_logo ? false : !!headerConfig.value?.branding?.site_name);
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

  // Refresh window state to ensure auth status is up to date
  onMounted(async () => {
    try {
      await WindowService.refresh();
    } catch (error) {
      console.warn('Failed to refresh window state:', error);
    }
  });

</script>

<template>
  <div class="w-full">
    <div class="flex flex-row items-center justify-between">
      <!-- Logo lockup -->
      <div class="flex items-center gap-3">
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
            class="flex items-center gap-3"
            :aria-label="logoConfig.alt">
            <img
              id="logo"
              :src="logoConfig.url"
              class="transition-transform"
              :class="isCustomDomainLogo ? 'size-20' : 'size-12'"
              :height="logoConfig.size"
              :width="logoConfig.size"
              :alt="logoConfig.alt" />
            <span
              v-if="logoConfig.showSiteName"
              class="font-brand text-lg font-bold leading-tight">
              {{ logoConfig.siteName }}
            </span>
          </a>
        </div>
      </div>
      <nav
        v-if="displayNavigation && navigationEnabled"
        role="navigation"
        :aria-label="t('web.layout.main_navigation')"
        class="flex flex-wrap items-center justify-end gap-4
          font-brand text-sm sm:text-base">
        <template v-if="isUserPresent">
          <!-- User Menu Dropdown -->
          <UserMenu
            :cust="windowProps.cust"
            :email="windowProps.email"
            :colonel="isColonel"
            :awaiting-mfa="windowProps.awaiting_mfa" />
        </template>

        <template v-else>
          <template v-if="windowProps.authentication.enabled">
            <!-- prettier-ignore-attribute class -->
            <router-link
              v-if="windowProps.authentication.signup"
              to="/signup"
              :title="t('web.homepage.signup_individual_and_business_plans')"
              class="font-bold text-gray-600 transition-colors duration-200
                hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ t('web.COMMON.header_create_account') }}
            </router-link>
            <span
              v-if="windowProps.authentication.signup && windowProps.authentication.signin"
              class="text-gray-400"
              aria-hidden="true"
              role="separator">
              |
            </span>
            <!-- prettier-ignore-attribute class -->
            <router-link
              v-if="windowProps.authentication.signin"
              to="/signin"
              :title="t('web.homepage.log_in_to_onetime_secret')"
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
