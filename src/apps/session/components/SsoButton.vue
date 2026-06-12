<!-- src/apps/session/components/SsoButton.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { submitSsoLogin } from '@/shared/utils/sso';
import { ref } from 'vue';

export interface Props {
  /**
   * SSO route name used to build the POST action URL.
   * Corresponds to the `name:` option in auth.omniauth_provider.
   * Example: 'oidc', 'google', 'entra', 'github'
   */
  routeName: string;

  /**
   * Human-readable label for the button.
   * Example: 'Google', 'Microsoft Entra ID', 'GitHub'
   * Falls back to generic SSO label when not provided.
   */
  displayName?: string;

  /**
   * URL to redirect back to after successful SSO authentication.
   * Example: '/invite/abc123'
   * When provided, this is passed to the backend as form data.
   */
  redirect?: string;
}

const props = withDefaults(defineProps<Props>(), {
  displayName: '',
  redirect: '',
});

const { t } = useI18n();
const csrfStore = useCsrfStore();

const isLoading = ref(false);

/**
 * Initiates SSO login by submitting a form POST to /auth/sso/:provider,
 * which triggers the OmniAuth flow and redirects to the identity provider.
 *
 * The form submission navigates away from the page, so there's no response
 * to handle and no need to reset isLoading.
 */
const handleSsoLogin = () => {
  isLoading.value = true;
  submitSsoLogin({
    routeName: props.routeName,
    shrimp: csrfStore.shrimp,
    redirect: props.redirect || undefined,
  });
};
</script>

<template>
  <div>
    <!-- SSO Button -->
    <button
      type="button"
      @click="handleSsoLogin"
      :disabled="isLoading"
      class="group relative flex w-full items-center justify-center gap-2
             rounded-md border border-gray-300 bg-white px-4 py-2
             text-lg font-medium text-gray-700
             transition-colors duration-200
             hover:bg-gray-50
             focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
             disabled:cursor-not-allowed disabled:opacity-50
             dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200
             dark:hover:bg-gray-600 dark:focus:ring-offset-gray-800"
      data-testid="sso-button">
      <span v-if="isLoading" class="flex items-center gap-2">
        <svg
          class="size-5 animate-spin motion-reduce:animate-none text-gray-500 dark:text-gray-400"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          aria-hidden="true">
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4" />
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
        </svg>
        {{ t('web.auth.sso.signing_in') }}
      </span>
      <template v-else>
        <OIcon
          collection="heroicons"
          name="solid-building-office"
          size="5"
          class="text-gray-500 dark:text-gray-400"
          aria-hidden="true" />
        <!-- Use provider-specific name if configured, otherwise generic SSO label -->
        {{ displayName ? t('web.login.sign_in_with_provider', { provider: displayName }) : t('web.login.sign_in_with_sso') }}
      </template>
    </button>
  </div>
</template>
