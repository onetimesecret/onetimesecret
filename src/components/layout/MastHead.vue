<!-- src/components/layout/Masthead.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import HeaderUserNav from '@/components/layout/HeaderUserNav.vue';
  import SettingsModal from '@/components/modals/SettingsModal.vue';
  import DefaultLogo from '@/components/logos/DefaultLogo.vue';
  import { WindowService } from '@/services/window.service';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, ref, watch, type Component } from 'vue';
  import { useI18n } from 'vue-i18n';
import { shallowRef } from 'vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  // Make window properties reactive by using computed
  const windowProps = computed(() => WindowService.getMultiple([
    'authentication',
    'authenticated',
    'cust',
    'ui',
  ]));

  const isColonel = computed(() => windowProps.value.cust?.role === 'colonel');

  // i18n setup
  const { t } = useI18n();

  // Header configuration
  const headerConfig = computed(() => windowProps.value.ui?.header);

  // Default logo component for fallback
  const DEFAULT_LOGO = 'DefaultLogo.vue';

  // Helper functions for logo configuration
  const getLogoUrl = () => props.logo?.url || headerConfig.value?.branding?.logo?.url || DEFAULT_LOGO;
  const getLogoAlt = () => props.logo?.alt || headerConfig.value?.branding?.logo?.alt || t('one-time-secret-literal');
  const getLogoHref = () => props.logo?.href || headerConfig.value?.branding?.logo?.link_to || '/';
  const getLogoSize = () => props.logo?.size || 64;
  const getShowSiteName = () => props.logo?.showSiteName ?? !!headerConfig.value?.branding?.site_name;
  const getSiteName = () => props.logo?.siteName || headerConfig.value?.branding?.site_name || t('one-time-secret-literal');
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
      const module = await import(`@/components/logos/${componentName}.vue`);
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
      const module = await import(`@/components/logos/${defaultComponent}.vue`);
      logoComponent.value = module.default;
      console.info(`Loaded fallback logo: ${defaultComponent}`);
    } catch (fallbackError) {
      console.error(`Failed to load fallback logo: ${DEFAULT_LOGO}`, fallbackError);
      logoComponent.value = null;
    }
  };

  // Watch for changes to logoUrl and load Vue component if needed
  watch(() => logoConfig.value.url, loadLogoComponent, { immediate: true });

  // Reactive state
  const isSettingsModalOpen = ref(false);

  // Methods
  const openSettingsModal = () => {
    isSettingsModalOpen.value = true;
  };

  const closeSettingsModal = () => {
    isSettingsModalOpen.value = false;
  };

</script>

<template>
  <div class="w-full">
    <div class="flex flex-col items-center justify-between sm:flex-row">
      <!-- Logo lockup -->
      <div class="mb-4 flex items-center justify-between gap-3 sm:mb-0">

        <div v-if="isVueComponent">
          <component
            :is="logoComponent"
            id="logo"
            v-if="logoComponent"
            v-bind="logoConfig"
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
              class="size-12 transition-transform"
              :height="logoConfig.size"
              :width="logoConfig.size"
              :alt="logoConfig.alt" />
            <span
              v-if="logoConfig.showSiteName"
              class="text-lg font-bold text-gray-800 dark:text-gray-100">
              {{ logoConfig.siteName }}
            </span>
          </a>
        </div>
      </div>
      <nav
        v-if="displayNavigation && navigationEnabled"
        role="navigation"
        :aria-label="t('main-navigation')"
        class="flex flex-wrap items-center justify-center gap-4
          font-brand text-sm sm:justify-end sm:text-base">
        <template v-if="windowProps.authenticated && windowProps.cust">
          <HeaderUserNav
            :cust="windowProps.cust"
            :colonel="isColonel" />
          <!-- prettier-ignore-attribute class -->
          <button
            @click="openSettingsModal"
            class="text-xl text-gray-600 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
            :aria-label="t('web.COMMON.header_settings')"
            :title="t('web.COMMON.header_settings')">
            <OIcon
              class="size-5"
              collection="material-symbols"
              name="settings-outline"
              aria-hidden="true" />
          </button>

          <SettingsModal
            :is-open="isSettingsModalOpen"

            @close="closeSettingsModal" />

          <span
            class="text-gray-400"
            role="separator">
            |
          </span>
          <!-- prettier-ignore-attribute class -->
          <router-link
            to="/logout"
            class="text-gray-600 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
            :title="t('web.COMMON.header_logout')"
            :aria-label="t('web.COMMON.header_logout')">
            <OIcon
              class="size-5"
              collection="heroicons"
              name="arrow-right-on-rectangle-solid"
              aria-hidden="true" />
          </router-link>
        </template>

        <template v-else>
          <template v-if="windowProps.authentication.enabled">
            <!-- prettier-ignore-attribute class -->
            <router-link
              v-if="windowProps.authentication.signup"
              to="/signup"
              :title="t('signup-individual-and-business-plans')"
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
              :title="t('log-in-to-onetime-secret')"
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
