<!-- src/apps/session/views/Login.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import AuthMethodSelector from '@/apps/session/components/AuthMethodSelector.vue';
import AuthView from '@/apps/session/components/AuthView.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useLanguageStore } from '@/shared/stores/languageStore';
import { hasPasswordlessMethods } from '@/utils/features';
import { storeToRefs } from 'pinia';
import { ref, computed, onMounted, type ComponentPublicInstance } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const languageStore = useLanguageStore();
const bootstrapStore = useBootstrapStore();
const { authentication } = storeToRefs(bootstrapStore);
const signupEnabled = computed(() => authentication.value.signup);

// Handle auth errors passed via query params (from SSO/magic link failures)
const authError = ref<string | null>(null);

const authErrorMessages: Record<string, string> = {
  sso_failed: 'web.login.errors.sso_failed',
  token_missing: 'web.login.errors.token_missing',
  token_expired: 'web.login.errors.token_expired',
  token_invalid: 'web.login.errors.token_invalid',
};

onMounted(() => {
  const errorCode = route.query.auth_error;
  if (typeof errorCode === 'string' && errorCode in authErrorMessages) {
    authError.value = t(authErrorMessages[errorCode]);
    // Clear the query param to prevent showing error on refresh
    router.replace({ query: { ...route.query, auth_error: undefined } });
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
    :heading="t('web.COMMON.login_to_your_account')"
    heading-id="signin-heading"
    :with-subheading="true"
    :hide-icon="false"
    :hide-background-icon="false"
    :show-return-home="false">
    <template #form>
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
        @mode-change="handleModeChange" />
    </template>
    <template #footer>
      <nav
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
