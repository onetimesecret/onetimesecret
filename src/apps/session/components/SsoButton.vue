<!-- src/apps/session/components/SsoButton.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { ref, computed } from 'vue';

const { t } = useI18n();
const csrfStore = useCsrfStore();
const bootstrapStore = useBootstrapStore();

const isLoading = ref(false);

/**
 * SSO provider display name from server configuration.
 * Falls back to null if not configured (uses generic "SSO" label).
 */
const providerName = computed(() => {
  const omniauth = bootstrapStore.features?.omniauth;
  if (typeof omniauth === 'object' && omniauth !== null) {
    return omniauth.provider_name || null;
  }
  return null;
});

/**
 * Initiates SSO login by submitting a form to the OIDC endpoint.
 * This creates a traditional form POST to /auth/sso/oidc which triggers
 * the OmniAuth flow and redirects to the identity provider.
 */
const handleSsoLogin = () => {
  isLoading.value = true;

  // Create and submit a form to POST to the SSO endpoint
  // This needs to be a form submission (not fetch) because it redirects to the IdP
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = '/auth/sso/oidc';

  /**
   * Add CSRF token for Rack::Protection::AuthenticityToken validation.
   *
   * The field is named 'shrimp' for historical/project-specific reasons.
   * The backend Rack::Protection::AuthenticityToken middleware is configured
   * with `authenticity_param: 'shrimp'` to accept this field name instead
   * of the default 'authenticity_token'.
   *
   * The value comes from session[:csrf] on the backend, which is serialized
   * into the page's bootstrap state and loaded into csrfStore on page load.
   */
  const csrfInput = document.createElement('input');
  csrfInput.type = 'hidden';
  csrfInput.name = 'shrimp';
  csrfInput.value = csrfStore.shrimp;
  form.appendChild(csrfInput);

  document.body.appendChild(form);
  form.submit();

  // Note: The form submission will navigate away from the page,
  // so we don't need to handle the response or reset isLoading
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
          class="size-5 animate-spin text-gray-500 dark:text-gray-400"
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
        {{ providerName ? t('web.login.sign_in_with_provider', { provider: providerName }) : t('web.login.sign_in_with_sso') }}
      </template>
    </button>
  </div>
</template>
