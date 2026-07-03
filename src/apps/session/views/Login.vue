<!-- src/apps/session/views/Login.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import AuthMethodSelector from '@/apps/session/components/AuthMethodSelector.vue';
import AuthView from '@/apps/session/components/AuthView.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useLanguageStore } from '@/shared/stores/languageStore';
import { hasPasswordlessMethods } from '@/utils/features';
import { storeToRefs } from 'pinia';
import { ref, computed, onMounted, type ComponentPublicInstance } from 'vue';
import { useRoute, useRouter, type LocationQueryRaw } from 'vue-router';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const languageStore = useLanguageStore();
const bootstrapStore = useBootstrapStore();
const { authentication, features } = storeToRefs(bootstrapStore);

// Per-domain sign-in disable (#3415). features.signin is the resolved
// availability for THIS domain context (AND of global AUTH_SIGNIN and the
// domain SigninConfig). Only an explicit false disables: the global-off case
// never reaches this page (the requiresFeature route guard redirects to '/'),
// so in practice this branch renders for domain-level disables.
const signinDisabled = computed(() => features.value?.signin === false);

// Custom domain branding: replace generic icon with domain logo on sign-in page
const identityStore = useProductIdentity();
const { isCustom } = storeToRefs(identityStore);
const { logoUri, displayName } = identityStore;
const signupEnabled = computed(
  () => !isCustom.value && authentication.value?.enabled && authentication.value?.signup
);

// Handle auth errors passed via query params (from SSO/magic link failures)
const authError = ref<string | null>(null);

// Post-verification return: useAuth.verifyAccount() redirects here with
// ?verified=1 after the user clicks the link in their welcome email. Read it
// synchronously (setup) so the value survives the onMounted query cleanup and
// is available on the first render when AuthMethodSelector mounts.
//   - verifiedNotice: drives a persistent success banner (vs. the transient toast)
//   - initialAuthMode: default to the password tab. Re-entering the password
//     they just chose is less redundant than another email link and confirms it
//     was typed correctly the first time.
const justVerified = route.query.verified === '1';
const verifiedNotice = ref(justVerified);
const initialAuthMode = justVerified ? 'password' : undefined;

const authErrorMessages: Record<string, string> = {
  sso_failed: 'web.login.errors.sso_failed',
  sso_not_configured: 'web.login.errors.sso_not_configured',
  token_missing: 'web.login.errors.token_missing',
  token_expired: 'web.login.errors.token_expired',
  token_invalid: 'web.login.errors.token_invalid',
  invalid_email: 'web.login.errors.invalid_email',
  domain_not_allowed: 'web.login.errors.domain_not_allowed',
};

onMounted(() => {
  const cleanupQuery: LocationQueryRaw = { ...route.query };
  let needsCleanup = false;

  const errorCode = route.query.auth_error;
  if (typeof errorCode === 'string' && errorCode.length > 0) {
    // Render a message for ANY auth_error code so a redirect from the auth
    // backend never lands on a silent/blank page (the "frozen loading screen"
    // in issue #3478). Known codes get their specific localized message;
    // unrecognized codes — e.g. from a backend newer than this bundle —
    // fall back to the generic SSO failure copy instead of rendering nothing.
    const messageKey = authErrorMessages[errorCode] ?? 'web.login.errors.sso_failed';
    authError.value = t(messageKey);
    cleanupQuery.auth_error = undefined;
    needsCleanup = true;
  }

  if (justVerified) {
    // Drop the one-shot flag so a refresh doesn't re-show the banner. The
    // captured verifiedNotice/initialAuthMode values are unaffected.
    cleanupQuery.verified = undefined;
    needsCleanup = true;
  }

  // Clear consumed query params to prevent re-triggering on refresh.
  if (needsCleanup) {
    router.replace({ query: cleanupQuery });
  }
});

// Check if any passwordless methods are enabled (magic links or webauthn)
const passwordlessEnabled = hasPasswordlessMethods();

// Build signup link with preserved query params (email, redirect)
const signupLink = computed(() => {
  const query: Record<string, string> = {};
  if (typeof route.query.email === 'string') {
    query.email = route.query.email;
  }
  if (typeof route.query.redirect === 'string') {
    query.redirect = route.query.redirect;
  }
  if (Object.keys(query).length > 0) {
    return { path: '/signup', query };
  }
  return '/signup';
});

type AuthMode = 'passkey' | 'passwordless' | 'password';

// Reference to AuthMethodSelector (kept for potential future use)
const authMethodSelectorRef = ref<ComponentPublicInstance<{ currentMode: AuthMode }> | null>(null);

// Mode change handler (kept for potential future use)
const handleModeChange = (_mode: AuthMode) => {
  // Footer is now consistent across modes, no need to track
};
</script>

<template>
  <AuthView
    :heading="signinDisabled ? t('web.login.signin_disabled_heading') : t('web.COMMON.login_to_your_account')"
    heading-id="signin-heading"
    :title-logo="isCustom ? logoUri : null"
    :title="isCustom ? displayName : null"
    :with-subheading="true"
    :hide-icon="false"
    :hide-background-icon="isCustom"
    :show-return-home="signinDisabled">
    <template #form>
      <!-- Sign-in disabled for this domain: friendly notice instead of the
           auth form. AuthView's return-home link provides the way out. -->
      <div
        v-if="signinDisabled"
        data-testid="signin-disabled-panel"
        class="space-y-3 py-2 text-center">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-10 text-gray-400 dark:text-gray-500"
          aria-hidden="true" />
        <p class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.login.signin_disabled_message') }}
        </p>
      </div>

      <template v-else>
        <!-- Post-verification success: persistent confirmation that the email
             was verified, shown until the user leaves the page. -->
        <div
          v-if="verifiedNotice"
          role="status"
          class="mb-4 flex items-center gap-2 rounded-md border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-800 dark:bg-green-900/20 dark:text-green-300"
          data-testid="signin-verified-notice">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="size-5 shrink-0 text-green-500 dark:text-green-400"
            aria-hidden="true" />
          <span>{{ t('web.login.verified_notice') }}</span>
        </div>

        <!-- Auth error from redirects (SSO failure, invalid magic link, etc.) -->
        <div
          v-if="authError"
          role="alert"
          class="mb-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/20 dark:text-red-400">
          {{ authError }}
        </div>

        <AuthMethodSelector
          ref="authMethodSelectorRef"
          :locale="languageStore.currentLocale ?? ''"
          :initial-mode="initialAuthMode"
          @mode-change="handleModeChange" />
      </template>
    </template>
    <template #footer>
      <nav
        v-if="!signinDisabled"
        aria-label="Additional sign-in options"
        class="flex items-center justify-center gap-2 text-sm">
        <!-- Consistent footer for all modes when passwordless methods enabled -->
        <template v-if="passwordlessEnabled">
          <router-link
            to="/help"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 hover:underline dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.login.need_help') }}
          </router-link>
          <template v-if="signupEnabled">
            <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
            <router-link
              :to="signupLink"
              class="text-gray-500 transition-colors duration-200 hover:text-gray-700 hover:underline dark:text-gray-400 dark:hover:text-gray-300">
              {{ t('web.login.create_account') }}
            </router-link>
          </template>
        </template>
        <!-- Password-only mode (no passwordless methods enabled): original footer -->
        <template v-else-if="signupEnabled">
          <span class="text-gray-600 dark:text-gray-400">
            {{ t('web.login.alternate_prefix') }}
          </span>
          {{ ' ' }}
          <router-link
            :to="signupLink"
            class="font-medium text-brand-600 underline transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.login.need_an_account') }}
          </router-link>
        </template>
      </nav>
    </template>
  </AuthView>
</template>
