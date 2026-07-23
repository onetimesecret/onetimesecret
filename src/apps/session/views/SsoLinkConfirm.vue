<!-- src/apps/session/views/SsoLinkConfirm.vue -->

<script setup lang="ts">
  import AuthView from '@/apps/session/components/AuthView.vue';
  import {
    ssoLinkConfirmRequiresMfa,
    type SsoLinkConfirmSuccess,
  } from '@/schemas/api/auth/responses/auth';
  import { loggingService } from '@/services/logging.service';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useSsoLinkConfirm } from '@/shared/composables/useSsoLinkConfirm';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { isValidInternalPath } from '@/utils/redirect';
  import { ref, onMounted, computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute, useRouter } from 'vue-router';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();

  const { pendingLink, confirmLink, fetchPendingLink, isLoading, error, clearError } =
    useSsoLinkConfirm();

  // Friendly provider labels; unknown providers fall back to a capitalized name
  // so a backend that adds a strategy still renders sensibly. Mirrors
  // ConnectedIdentities.vue / LinkSso.vue.
  const PROVIDER_LABELS: Record<string, string> = {
    oidc: 'OpenID Connect',
    entra: 'Microsoft Entra',
    github: 'GitHub',
    google: 'Google',
  };

  // Set when the display context cannot be loaded (GET failed) OR any confirm
  // (POST) fails: the single-use token is spent or the account moved, so there is
  // nothing to retry — render the terminal panel, not the consent CTA. The
  // specific reason lives in `error`.
  const linkUnavailable = ref(false);

  // Single-use token from the emailed link's path (scrubbed from diagnostics via
  // the route's sentryScrubParams).
  const token = computed(() => {
    const raw = route.params.token;
    return typeof raw === 'string' ? raw : '';
  });

  // Post-link destination from the query, if a safe internal path. Only used as a
  // fallback when the confirm response does not carry its own redirect target.
  const redirectPath = computed(() => {
    const redirect = route.query.redirect;
    if (typeof redirect !== 'string') return null;
    return isValidInternalPath(redirect) ? redirect : null;
  });

  const providerLabel = computed(() => {
    const provider = pendingLink.value?.provider;
    if (!provider) return '';
    return PROVIDER_LABELS[provider] ?? provider.charAt(0).toUpperCase() + provider.slice(1);
  });

  // Terminal-panel body: the specific dead-end reason when one was classified
  // (expired / conflict / invalidated), else the generic expired copy (e.g. the
  // token was missing from the URL entirely, so no fetch ran).
  const unavailableMessage = computed(
    () => error.value ?? t('web.sso_link_confirm.unavailable_message')
  );

  onMounted(async () => {
    // Already fully signed in (e.g. a stale link opened after a separate login):
    // nothing to link, go home.
    if (authStore.isFullyAuthenticated) {
      loggingService.debug('[SsoLinkConfirm] Already authenticated, redirecting to /');
      router.push('/');
      return;
    }

    if (!token.value) {
      loggingService.debug('[SsoLinkConfirm] Missing token — dead-end');
      linkUnavailable.value = true;
      return;
    }

    // DISPLAY-ONLY fetch: never mutates. The confirm (POST) only fires on the
    // user's explicit consent below — never auto-POST on load.
    const context = await fetchPendingLink(token.value);
    if (!context) {
      // Token spent / expired / unknown — render the terminal panel.
      linkUnavailable.value = true;
    }
  });

  // Handle a successful confirm. Mailbox proof succeeded server-side and the
  // identity is bound; for an MFA account only the FIRST factor is done. Mirror
  // the normal Login flow EXACTLY: hand an MFA account off to the shared
  // /mfa-verify challenge WITHOUT marking it fully authenticated; otherwise
  // complete the sign-in and navigate to the safest available destination.
  const handleConfirmSuccess = async (result: SsoLinkConfirmSuccess) => {
    if (ssoLinkConfirmRequiresMfa(result)) {
      loggingService.debug('[SsoLinkConfirm] MFA required, routing to /mfa-verify');
      // Mark awaiting_mfa (NOT authenticated) so the MFA route guard permits
      // /mfa-verify; preserve any ?redirect for the post-verify hop.
      bootstrapStore.update({ awaiting_mfa: true, authenticated: false });
      router.push({
        path: '/mfa-verify',
        query: redirectPath.value ? { redirect: redirectPath.value } : undefined,
      });
      return;
    }

    loggingService.debug('[SsoLinkConfirm] Link confirmed, completing sign-in');
    await authStore.setAuthenticated(true);

    // Prefer the backend's redirect target when it is a safe internal path;
    // otherwise the ?redirect query param; otherwise the dashboard.
    const fromResponse =
      result.redirect && isValidInternalPath(result.redirect) ? result.redirect : null;
    const destination = fromResponse ?? redirectPath.value ?? '/';
    router.push(destination);
  };

  // Confirm the link. Mailbox possession (the emailed token) is the proof — no
  // password. Success binds the identity and establishes the session; any failure
  // is terminal (single-use token consumed / account moved), so flip to the
  // dead-end panel carrying the specific reason.
  const handleConfirm = async () => {
    if (isLoading.value) return;

    clearError();
    const result = await confirmLink(token.value);

    if (result) {
      await handleConfirmSuccess(result);
      return;
    }

    linkUnavailable.value = true;
  };

  // Cancel / dead-end: the account is PASSWORDLESS, so there is no existing
  // password to sign in with — send the user back to /signin to start SSO again
  // (which re-issues a fresh verification email). Not the Connected Identities
  // pointer Phase 3 uses (that flow needs a password to reach).
  const goToSignIn = () => {
    router.push('/signin');
  };

  const handleCancel = () => {
    clearError();
    goToSignIn();
  };
</script>

<template>
  <AuthView
    :heading="t('web.sso_link_confirm.title')"
    heading-id="sso-link-confirm-heading"
    :with-subheading="false"
    :show-return-home="false">
    <template #form>
      <div class="space-y-6">
        <!-- Dead-end: token missing / expired / spent, or the confirm failed
             (conflict / invalidated). Terminal — the single-use token is gone. -->
        <div
          v-if="linkUnavailable"
          data-testid="sso-link-confirm-unavailable"
          class="space-y-4 text-center">
          <OIcon
            collection="heroicons"
            name="lock-closed"
            class="mx-auto size-10 text-gray-400 dark:text-gray-500"
            aria-hidden="true" />
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.sso_link_confirm.unavailable_title') }}
          </h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            {{ unavailableMessage }}
          </p>
          <button
            @click="goToSignIn"
            type="button"
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
            data-testid="sso-link-confirm-unavailable-action">
            {{ t('web.sso_link_confirm.unavailable_action') }}
          </button>
        </div>

        <!-- Loading the display context -->
        <div
          v-else-if="isLoading && !pendingLink"
          aria-live="polite"
          class="py-4 text-center text-sm text-gray-600 dark:text-gray-400"
          data-testid="sso-link-confirm-loading">
          {{ t('web.COMMON.form_processing') }}
        </div>

        <!-- Consent: name the provider + claimed email, then a single Confirm CTA.
             Mailbox possession is the proof — there is NO password field. -->
        <template v-else-if="pendingLink">
          <p
            id="sso-link-confirm-instructions"
            class="text-center text-gray-600 dark:text-gray-400"
            data-testid="sso-link-confirm-prompt">
            {{ t('web.sso_link_confirm.prompt', { provider: providerLabel, email: pendingLink.email }) }}
          </p>

          <button
            @click="handleConfirm"
            type="button"
            :disabled="isLoading"
            :aria-disabled="isLoading ? 'true' : undefined"
            aria-describedby="sso-link-confirm-instructions"
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            data-testid="sso-link-confirm-submit">
            <span v-if="isLoading">{{ t('web.COMMON.processing') }}</span>
            <span v-else>{{ t('web.sso_link_confirm.submit') }}</span>
          </button>

          <!-- Loading state announcement (screen reader only) -->
          <div
            v-if="isLoading"
            aria-live="polite"
            aria-atomic="true"
            class="sr-only">
            {{ t('web.COMMON.form_processing') }}
          </div>
        </template>
      </div>
    </template>

    <!-- Footer: cancel abandons linking and returns to sign in -->
    <template #footer>
      <div
        v-if="!linkUnavailable"
        class="border-t border-gray-200 pt-4 dark:border-gray-700">
        <nav class="flex items-center justify-center gap-2 text-sm">
          <button
            @click="handleCancel"
            type="button"
            :disabled="isLoading"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400 dark:hover:text-gray-300"
            data-testid="sso-link-confirm-cancel">
            {{ t('web.sso_link_confirm.cancel') }}
          </button>
        </nav>
      </div>
    </template>
  </AuthView>
</template>
