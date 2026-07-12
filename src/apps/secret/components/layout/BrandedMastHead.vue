<!-- src/apps/secret/components/layout/BrandedMastHead.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import BrandedHero from '@/apps/secret/components/branded/BrandedHero.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { isSsoEnabled, isOrgsSsoEnabled } from '@/utils/features';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';
  import { storeToRefs } from 'pinia';

  const { t } = useI18n();

  const bootstrapStore = useBootstrapStore();
  const { authentication, homepage_config } = storeToRefs(bootstrapStore);

  /**
   * Per-domain gate for the auth nav links. Defaults to disabled — the links
   * stay hidden unless the domain's homepage_config explicitly opts in
   * (signup_enabled/signin_enabled === true). A missing homepage_config (or a
   * missing field) reads as disabled. The frontend still ANDs the system
   * authentication flags with these domain-level toggles — the domain owner
   * can only narrow, never broaden.
   */
  const domainSignupEnabled = computed(() => homepage_config.value?.signup_enabled === true);
  const domainSigninEnabled = computed(() => homepage_config.value?.signin_enabled === true);

  /**
   * Show Sign In link when signin route is available AND the domain hasn't
   * disabled it AND either:
   * - Platform authentication is enabled (authentication.enabled), OR
   * - Platform-level SSO is configured (features.sso.enabled), OR
   * - Domain-level SSO is enabled (features.organizations.sso_enabled)
   *
   * This ensures custom domains with SSO see the sign-in link even when
   * platform-level AUTH_ENABLED=false.
   */
  const showSignIn = computed(() => {
    const hasSigninRoute = authentication.value?.signin === true;
    const platformAuthEnabled = authentication.value?.enabled === true;
    const platformSsoEnabled = isSsoEnabled();
    const domainSsoEnabled = isOrgsSsoEnabled();

    return hasSigninRoute
      && domainSigninEnabled.value
      && (platformAuthEnabled || platformSsoEnabled || domainSsoEnabled);
  });

  /**
   * Sign Up requires platform authentication — SSO users are provisioned
   * through their identity provider, not the platform signup flow, so we
   * mirror the canonical MastHead gating here rather than the broader SSO
   * gating used for Sign In.
   */
  const showSignUp = computed(() =>
    authentication.value?.enabled === true
    && authentication.value?.signup === true
    && domainSignupEnabled.value
  );

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
      class="absolute right-4 top-4 flex items-center gap-2"
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
