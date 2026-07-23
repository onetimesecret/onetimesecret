<!-- src/apps/session/views/LinkSso.vue -->

<script setup lang="ts">
  import AuthView from '@/apps/session/components/AuthView.vue';
  import { loggingService } from '@/services/logging.service';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useLinkSso } from '@/shared/composables/useLinkSso';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { isValidInternalPath } from '@/utils/redirect';
  import { ref, onMounted, computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute, useRouter } from 'vue-router';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const authStore = useAuthStore();

  const { challenge, verifyLink, fetchChallenge, isLoading, error, errorCode, clearError } =
    useLinkSso();

  // Phase 2 Connected Identities panel — where the H-3 refusal points on
  // cancel / dead-end. An UNAUTHENTICATED user cannot open it directly, so we
  // route through /signin carrying this as the post-login destination.
  const CONNECT_REDIRECT = '/account/settings/security/connections';

  // Friendly provider labels; unknown providers fall back to a capitalized name
  // so a backend that adds a strategy still renders sensibly. Mirrors
  // ConnectedIdentities.vue.
  const PROVIDER_LABELS: Record<string, string> = {
    oidc: 'OpenID Connect',
    entra: 'Microsoft Entra',
    github: 'GitHub',
    google: 'Google',
  };

  const password = ref('');
  const passwordInputRef = ref<HTMLInputElement | null>(null);
  // Set when the challenge context cannot be loaded or the token is spent: there
  // is nothing to prove against, so render the dead-end panel, not the form.
  const challengeUnavailable = ref(false);

  // Single-use challenge token from the interstitial URL (path param, scrubbed
  // from diagnostics via the route's sentryScrubParams).
  const token = computed(() => {
    const raw = route.params.token;
    return typeof raw === 'string' ? raw : '';
  });

  // Post-link destination from the query, if a safe internal path. Only used as
  // a fallback when the verify response does not carry its own redirect target.
  const redirectPath = computed(() => {
    const redirect = route.query.redirect;
    if (typeof redirect !== 'string') return null;
    return isValidInternalPath(redirect) ? redirect : null;
  });

  const providerLabel = computed(() => {
    const provider = challenge.value?.provider;
    if (!provider) return '';
    return PROVIDER_LABELS[provider] ?? provider.charAt(0).toUpperCase() + provider.slice(1);
  });

  onMounted(async () => {
    // Already fully signed in (e.g. a stale interstitial link opened after a
    // separate login): nothing to link, go home.
    if (authStore.isFullyAuthenticated) {
      loggingService.debug('[LinkSso] Already authenticated, redirecting to /');
      router.push('/');
      return;
    }

    if (!token.value) {
      loggingService.debug('[LinkSso] Missing challenge token — dead-end');
      challengeUnavailable.value = true;
      return;
    }

    const context = await fetchChallenge(token.value);
    if (!context) {
      // Token spent / expired / unknown — keep the H-3 refusal, point at settings.
      challengeUnavailable.value = true;
    }
  });

  // Verify the account's EXISTING password. Success establishes the session
  // server-side; sync client auth state and navigate. Wrong password → retry;
  // spent/expired token → dead-end.
  const handleVerify = async () => {
    if (!password.value || isLoading.value) return;

    clearError();
    const result = await verifyLink(token.value, password.value);

    if (result) {
      loggingService.debug('[LinkSso] Link verified, completing sign-in');
      await authStore.setAuthenticated(true);

      // Prefer the backend's redirect target when it is a safe internal path;
      // otherwise the ?redirect query param; otherwise the dashboard.
      const fromResponse =
        result.redirect && isValidInternalPath(result.redirect) ? result.redirect : null;
      const destination = fromResponse ?? redirectPath.value ?? '/';
      router.push(destination);
      return;
    }

    if (errorCode.value === 'invalid_token') {
      // Nothing left to prove against — fall through to the dead-end panel.
      challengeUnavailable.value = true;
      return;
    }

    // Wrong password: clear the field and let the user try again.
    password.value = '';
    passwordInputRef.value?.focus();
  };

  // Cancel / dead-end: an unauthenticated user is sent to sign in with their
  // existing method, carrying the Connected Identities panel as the post-login
  // destination plus an explanatory pointer (Login.vue renders link_sso_failed).
  const goToSignInFallback = () => {
    router.push({
      path: '/signin',
      query: { auth_error: 'link_sso_failed', redirect: CONNECT_REDIRECT },
    });
  };

  const handleCancel = () => {
    clearError();
    goToSignInFallback();
  };
</script>

<template>
  <AuthView
    :heading="t('web.link_sso.title')"
    heading-id="link-sso-heading"
    :with-subheading="false"
    :show-return-home="false">
    <template #form>
      <div class="space-y-6">
        <!-- Dead-end: token missing / expired / spent. Keep the H-3 refusal and
             point the user at the Phase 2 settings flow. -->
        <div
          v-if="challengeUnavailable"
          data-testid="link-sso-unavailable"
          class="space-y-4 text-center">
          <OIcon
            collection="heroicons"
            name="lock-closed"
            class="mx-auto size-10 text-gray-400 dark:text-gray-500"
            aria-hidden="true" />
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.link_sso.unavailable_title') }}
          </h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.link_sso.unavailable_message') }}
          </p>
          <button
            @click="goToSignInFallback"
            type="button"
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
            data-testid="link-sso-unavailable-action">
            {{ t('web.link_sso.unavailable_action') }}
          </button>
        </div>

        <!-- Loading the challenge context -->
        <div
          v-else-if="isLoading && !challenge"
          aria-live="polite"
          class="py-4 text-center text-sm text-gray-600 dark:text-gray-400"
          data-testid="link-sso-loading">
          {{ t('web.COMMON.form_processing') }}
        </div>

        <!-- Password challenge -->
        <template v-else-if="challenge">
          <p
            id="link-sso-instructions"
            class="text-center text-gray-600 dark:text-gray-400"
            data-testid="link-sso-prompt">
            {{ t('web.link_sso.prompt', { provider: providerLabel, email: challenge.email }) }}
          </p>

          <form
            @submit.prevent="handleVerify"
            class="space-y-4">
            <div>
              <label
                for="link-sso-password"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.link_sso.password_label') }}
              </label>
              <input
                id="link-sso-password"
                ref="passwordInputRef"
                v-model="password"
                type="password"
                autocomplete="current-password"
                :disabled="isLoading"
                :aria-invalid="error ? 'true' : undefined"
                :aria-describedby="error ? 'link-sso-error' : 'link-sso-instructions'"
                :placeholder="t('web.link_sso.password_placeholder')"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
                data-testid="link-sso-password-input" />
            </div>

            <!-- Error message (wrong password stays inline; token errors dead-end) -->
            <div
              v-if="error"
              id="link-sso-error"
              class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
              role="alert"
              aria-live="assertive"
              aria-atomic="true"
              data-testid="link-sso-error">
              <p class="text-sm text-red-800 dark:text-red-200">
                {{ error }}
              </p>
            </div>

            <button
              type="submit"
              :disabled="!password || isLoading"
              :aria-disabled="!password || isLoading ? 'true' : undefined"
              class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              data-testid="link-sso-submit">
              <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
              <span v-else>{{ t('web.link_sso.submit') }}</span>
            </button>

            <!-- Loading state announcement (screen reader only) -->
            <div
              v-if="isLoading"
              aria-live="polite"
              aria-atomic="true"
              class="sr-only">
              {{ t('web.COMMON.form_processing') }}
            </div>
          </form>
        </template>
      </div>
    </template>

    <!-- Footer: cancel returns to the sign-in / settings flow -->
    <template #footer>
      <div
        v-if="!challengeUnavailable"
        class="border-t border-gray-200 pt-4 dark:border-gray-700">
        <nav class="flex items-center justify-center gap-2 text-sm">
          <button
            @click="handleCancel"
            type="button"
            :disabled="isLoading"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400 dark:hover:text-gray-300"
            data-testid="link-sso-cancel">
            {{ t('web.link_sso.cancel') }}
          </button>
        </nav>
      </div>
    </template>
  </AuthView>
</template>
