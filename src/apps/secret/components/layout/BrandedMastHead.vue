<!-- src/apps/secret/components/layout/BrandedMastHead.vue -->

<script setup lang="ts">
  import BrandedHero from '@/apps/secret/components/branded/BrandedHero.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const bootstrapStore = useBootstrapStore();
  const { homepage_config } = storeToRefs(bootstrapStore);

  /**
   * Show the Create Account / Sign In links based on the RESOLVED per-domain
   * auth availability computed by the backend. Custom domains default OFF:
   * DomainSerializer#effective_* only reports true when the domain owner has
   * explicitly enabled sign-in / sign-up via SigninConfig / SignupConfig (the
   * /domains/:id/signin + /signup settings pages), and the global kill switch
   * (AUTH_ENABLED / AUTH_SIGNUP / AUTH_SIGNIN) can still force it off. The
   * frontend only DISPLAYS that resolved truth — it never re-derives it. A
   * missing homepage_config (canonical/subdomain request, or a legacy record)
   * reads as disabled.
   */
  const showSignUp = computed(() => homepage_config.value?.signup_enabled === true);
  const showSignIn = computed(() => homepage_config.value?.signin_enabled === true);

  interface Props extends LayoutProps {
    headertext: string;
    subtext: string;
  }

  withDefaults(defineProps<Props>(), {
    displayMasthead: true,
    displayNavigation: true,
    headertext: 'secure-links',
    subtext: 'a-trusted-way-to-share-sensitive-information-etc',
  });
</script>

<template>
  <div class="relative bg-white py-8 transition-colors duration-200 dark:bg-gray-900">
    <!-- Auth Links (Sign Up / Sign In for custom domain users) -->
    <nav
      v-if="showSignUp || showSignIn"
      class="absolute top-4 right-4 flex items-center gap-2"
      role="navigation"
      :aria-label="t('web.layout.main_navigation')">
      <router-link
        v-if="showSignUp"
        to="/signup"
        :title="t('web.homepage.signup_individual_and_business_plans')"
        data-testid="branded-signup-link"
        class="text-sm font-bold text-gray-600 transition-colors duration-200
          hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
        {{ t('web.COMMON.header_create_account') }}
      </router-link>
      <span
        v-if="showSignUp && showSignIn"
        class="text-sm text-gray-400"
        aria-hidden="true"
        role="separator">
        |
      </span>
      <router-link
        v-if="showSignIn"
        to="/signin"
        :title="t('web.homepage.log_in_to_onetime_secret')"
        data-testid="branded-signin-link"
        class="text-sm text-gray-600 transition-colors duration-200
          hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
        {{ t('web.COMMON.header_sign_in') }}
      </router-link>
    </nav>

    <div class="container mx-auto max-w-2xl px-4">
      <BrandedHero
        :title="headertext"
        :subtitle="subtext"
        logo-link-to="/" />
    </div>
  </div>
</template>
