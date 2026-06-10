<!-- src/shared/components/layout/TransactionalHeader.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import MastHead from '@/shared/components/layout/MastHead.vue';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';

  const { t } = useI18n();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayHeader: true,
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const { authentication, homepage_config, headerConfig } = storeToRefs(bootstrapStore);

  const isUserPresent = computed(() => authStore.isUserPresent);

  // Operator-level header gate (HEADER_ENABLED). When disabled, the entire
  // <header> banner landmark collapses — no empty landmark, no padding band.
  // Distinct from displayHeader (per-route concern). Both must hold to render.
  const headerEnabled = computed(() => headerConfig.value?.enabled !== false);

  // Per-domain link toggles (custom-domain homepage). Default to enabled
  // when no domain config exists. System-level flags remain the master
  // switch — both layers must be true for the link to render.
  const showDomainSignup = computed(() => homepage_config.value?.signup_enabled !== false);
  const showDomainSignin = computed(() => homepage_config.value?.signin_enabled !== false);

  // Show minimal nav when MastHead is hidden but navigation is enabled.
  // This handles custom domain pages where the logo lives in page content
  // but Sign In still needs a layout-level home.
  const showMinimalNav = computed(
    () => !props.displayMasthead && props.displayNavigation && !isUserPresent.value
  );
</script>

<template>
  <header
    v-if="displayHeader && headerEnabled"
    class="bg-white dark:bg-gray-900">
    <div class="container mx-auto min-w-[320px] max-w-2xl p-4">
      <MastHead v-if="displayMasthead" v-bind="props" />

      <!-- Minimal nav for custom domain pages without MastHead.
           max-w-xl aligns with BrandedHomepage content column. -->
      <nav
        v-else-if="showMinimalNav"
        role="navigation"
        :aria-label="t('web.layout.main_navigation')"
        class="mx-auto flex w-full max-w-xl justify-end font-brand text-sm sm:text-base">
        <template v-if="authentication?.enabled">
          <router-link
            v-if="authentication?.signup && showDomainSignup"
            to="/signup"
            :title="t('web.homepage.signup_individual_and_business_plans')"
            data-testid="header-signup-link"
            class="font-bold text-gray-600 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ t('web.COMMON.header_create_account') }}
          </router-link>
          <span
            v-if="authentication?.signup && showDomainSignup && authentication?.signin && showDomainSignin"
            class="mx-2 text-gray-400"
            aria-hidden="true"
            role="separator">
            |
          </span>
          <router-link
            v-if="authentication?.signin && showDomainSignin"
            to="/signin"
            :title="t('web.homepage.log_in_to_onetime_secret')"
            data-testid="header-signin-link"
            class="text-gray-600 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ t('web.COMMON.header_sign_in') }}
          </router-link>
        </template>
      </nav>
    </div>
  </header>
</template>
