<!-- src/apps/session/components/PasswordlessFirstSignIn.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { TabGroup, TabList, Tab, TabPanels, TabPanel } from '@headlessui/vue';
import LockoutAlert from '@/apps/session/components/LockoutAlert.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { useMagicLink } from '@/shared/composables/useMagicLink';
import { useWebAuthn } from '@/shared/composables/useWebAuthn';
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();

export interface Props {
  locale?: string;
  magicLinksEnabled?: boolean;
  webauthnEnabled?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  locale: 'en',
  magicLinksEnabled: true,
  webauthnEnabled: false,
});

type AuthMode = 'passkey' | 'passwordless' | 'password';

const emit = defineEmits<{
  (e: 'mode-change', mode: AuthMode): void;
}>();

// Build dynamic tabs based on enabled features
interface TabConfig {
  id: AuthMode;
  labelKey: string;
}

const tabs = computed<TabConfig[]>(() => {
  const result: TabConfig[] = [];

  // Passkey tab (first if enabled)
  if (props.webauthnEnabled) {
    result.push({ id: 'passkey', labelKey: 'web.login.tab_passkey' });
  }

  // Magic Link tab
  if (props.magicLinksEnabled) {
    result.push({ id: 'passwordless', labelKey: 'web.login.tab_magic_link' });
  }

  // Password tab (always present)
  result.push({ id: 'password', labelKey: 'web.login.tab_password' });

  return result;
});

// Tab index management
const selectedTabIndex = ref(0);

// Prefill email from query param (e.g., from invitation flow)
const emailFromQuery = typeof route.query.email === 'string' ? route.query.email : '';
const email = ref(emailFromQuery);
const webauthnEmail = ref(emailFromQuery);

// Current mode derived from tab index
const currentMode = computed<AuthMode>(() => tabs.value[selectedTabIndex.value]?.id ?? 'password');

// Password mode state
const password = ref('');
const rememberMe = ref(false);
const showPassword = ref(false);

// Auth composables
const { login, isLoading: isPasswordLoading, error: passwordError, lockoutStatus, clearErrors } = useAuth();
const { requestMagicLink, sent: magicLinkSent, isLoading: isMagicLinkLoading, error: magicLinkError, clearState: clearMagicLinkState } = useMagicLink();
const {
  supported: webauthnSupported,
  isLoading: isWebAuthnLoading,
  error: webauthnError,
  authenticateWebAuthn,
  clearError: clearWebAuthnError
} = useWebAuthn();

// Combined loading state
const isLoading = computed(() =>
  isPasswordLoading.value || isMagicLinkLoading.value || isWebAuthnLoading.value
);

// Current error based on mode
const currentError = computed(() => {
  switch (currentMode.value) {
    case 'passkey':
      return webauthnError.value;
    case 'password':
      return passwordError.value;
    default:
      return magicLinkError.value;
  }
});

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

// Handle tab change from HeadlessUI
const handleTabChange = (index: number) => {
  selectedTabIndex.value = index;
  const mode = tabs.value[index]?.id ?? 'password';

  // Clear errors when switching tabs
  if (mode === 'passkey') {
    clearErrors();
    clearMagicLinkState();
    password.value = '';
  } else if (mode === 'passwordless') {
    clearErrors();
    clearWebAuthnError();
    password.value = '';
  } else {
    clearMagicLinkState();
    clearWebAuthnError();
  }

  emit('mode-change', mode);
};

const handlePasswordSubmit = async () => {
  clearErrors();
  await login(email.value, password.value, rememberMe.value);
};

const handleMagicLinkSubmit = async () => {
  await requestMagicLink(email.value);
};

const handleWebAuthnSubmit = async () => {
  await authenticateWebAuthn(webauthnEmail.value || undefined);
};

const handleTryAgain = () => {
  clearMagicLinkState();
  email.value = '';
};

// Find tab index by mode ID (available for future use)
const _getTabIndexByMode = (mode: AuthMode): number => tabs.value.findIndex(tab => tab.id === mode);

// Check if a specific tab is the passkey tab
const isPasskeyTab = (index: number): boolean => tabs.value[index]?.id === 'passkey';

// Check if a specific tab is the magic link tab
const isMagicLinkTab = (index: number): boolean => tabs.value[index]?.id === 'passwordless';

// Check if a specific tab is the password tab
const isPasswordTab = (index: number): boolean => tabs.value[index]?.id === 'password';
</script>

<template>
  <!-- Magic link sent success state -->
  <div v-if="magicLinkSent"
class="space-y-6"
data-testid="magic-link-sent">
    <div class="rounded-md bg-green-50 p-6 text-center dark:bg-green-900/20">
      <svg
        class="mx-auto size-12 text-green-600 dark:text-green-400"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M3 19v-8.93a2 2 0 01.89-1.664l7-4.666a2 2 0 012.22 0l7 4.666A2 2 0 0121 10.07V19M3 19a2 2 0 002 2h14a2 2 0 002-2M3 19l6.75-4.5M21 19l-6.75-4.5M3 10l6.75 4.5M21 10l-6.75 4.5m0 0l-1.14.76a2 2 0 01-2.22 0l-1.14-.76" />
      </svg>
      <h3 class="mt-4 text-lg font-medium text-green-900 dark:text-green-100">
        {{ t('web.auth.magicLink.checkEmail') }}
      </h3>
      <p class="mt-2 text-sm text-green-800 dark:text-green-200">
        {{ t('web.auth.magicLink.sentTo', { email }) }}
      </p>
      <p class="mt-3 text-xs text-green-700 dark:text-green-300">
        {{ t('web.auth.magicLink.linkExpiresIn') }}
      </p>
    </div>

    <button
      type="button"
      @click="handleTryAgain"
      class="text-sm text-brand-600 transition duration-300 ease-in-out hover:underline dark:text-brand-400"
      data-testid="try-different-email">
      {{ t('web.auth.magicLink.tryDifferentEmail') }}
    </button>
  </div>

  <!-- Main form with HeadlessUI tabs -->
  <TabGroup
    v-else
    :selected-index="selectedTabIndex"
    @change="handleTabChange"
    as="div"
    class="space-y-6"
    data-testid="auth-tabs">
    <!-- Tab list -->
    <TabList class="flex justify-center border-b border-gray-200 dark:border-gray-700">
      <Tab
        v-for="tab in tabs"
        :key="tab.id"
        v-slot="{ selected }"
        as="template">
        <button
          class="relative cursor-pointer px-5 py-3 text-base font-semibold transition-colors duration-200
                 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2
                 dark:focus-visible:ring-offset-gray-800"
          :class="[
            selected
              ? 'text-brand-600 dark:text-brand-400'
              : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
          ]"
          :data-testid="`tab-${tab.id}`">
          {{ t(tab.labelKey) }}
          <span
            v-if="selected"
            class="absolute inset-x-0 -bottom-px h-0.5 bg-brand-500 dark:bg-brand-400"
            aria-hidden="true"></span>
        </button>
      </Tab>
    </TabList>

    <!-- Tab panels -->
    <TabPanels>
      <TabPanel
        v-for="(tab, index) in tabs"
        :key="tab.id">
        <!-- Passkey panel -->
        <div v-if="isPasskeyTab(index)"
class="space-y-6"
data-testid="passkey-panel">
          <!-- Browser support warning -->
          <div
            v-if="!webauthnSupported"
            class="rounded-md bg-yellow-50 p-4 dark:bg-yellow-900/20"
            role="alert"
            data-testid="webauthn-not-supported">
            <div class="flex">
              <svg
                class="size-5 text-yellow-400"
                fill="currentColor"
                viewBox="0 0 20 20"
                aria-hidden="true">
                <path
                  fill-rule="evenodd"
                  d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                  clip-rule="evenodd" />
              </svg>
              <div class="ml-3">
                <p class="text-sm text-yellow-800 dark:text-yellow-200">
                  {{ t('web.auth.webauthn.notSupported') }}
                </p>
                <p class="mt-1 text-xs text-yellow-700 dark:text-yellow-300">
                  {{ t('web.auth.webauthn.requiresModernBrowser') }}
                </p>
              </div>
            </div>
          </div>

          <!-- WebAuthn form -->
          <form
            v-else
            @submit.prevent="handleWebAuthnSubmit"
            class="space-y-6">
            <!-- Error message -->
            <div
              v-if="currentError"
              class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
              role="alert"
              aria-live="assertive"
              aria-atomic="true"
              data-testid="webauthn-error">
              <p class="text-sm text-red-800 dark:text-red-200">
                {{ currentError }}
              </p>
            </div>

            <!-- Fingerprint icon -->
            <div class="flex justify-center">
              <div class="rounded-full bg-brand-100 p-4 dark:bg-brand-900/30">
                <svg
                  class="size-12 text-brand-600 dark:text-brand-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M7.864 4.243A7.5 7.5 0 0119.5 10.5c0 2.92-.556 5.709-1.568 8.268M5.742 6.364A7.465 7.465 0 004.5 10.5a7.464 7.464 0 01-1.15 3.993m1.989 3.559A11.209 11.209 0 008.25 10.5a3.75 3.75 0 117.5 0c0 .527-.021 1.049-.064 1.565M12 10.5a14.94 14.94 0 01-3.6 9.75m6.633-4.596a18.666 18.666 0 01-2.485 5.33" />
                </svg>
              </div>
            </div>

            <!-- Description -->
            <p class="text-center text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.auth.webauthn.description') }}
            </p>

            <!-- Optional email field for credential autofill -->
            <div>
              <label
                for="webauthn-email"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.COMMON.field_email') }}
                <span class="text-gray-500 dark:text-gray-400">({{ t('web.COMMON.optional') || 'optional' }})</span>
              </label>
              <input
                id="webauthn-email"
                name="email"
                type="email"
                autocomplete="username webauthn"
                :disabled="isLoading"
                class="block w-full appearance-none rounded-md
                       border border-gray-300 px-3 py-2 text-lg
                       text-gray-900 placeholder:text-gray-500
                       focus:border-brand-500 focus:outline-none focus:ring-brand-500
                       disabled:cursor-not-allowed disabled:opacity-50
                       dark:border-gray-600 dark:bg-gray-700 dark:text-white
                       dark:placeholder:text-gray-400 dark:focus:border-brand-500
                       dark:focus:ring-brand-500"
                :placeholder="t('web.COMMON.email_placeholder')"
                v-model="webauthnEmail"
                data-testid="webauthn-email-input" />
            </div>

            <!-- Submit button -->
            <div>
              <button
                type="submit"
                :disabled="isLoading"
                class="group relative flex w-full justify-center rounded-md
                       border border-transparent bg-brand-600 px-4 py-2
                       text-lg font-medium text-white hover:bg-brand-700
                       focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                       disabled:cursor-not-allowed disabled:opacity-50
                       dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800"
                data-testid="webauthn-submit">
                <span v-if="isLoading" class="flex items-center">
                  <svg
                    class="-ml-1 mr-3 size-5 animate-spin text-white"
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
                  {{ t('web.auth.webauthn.processing') }}
                </span>
                <span v-else>{{ t('web.auth.webauthn.signIn') }}</span>
              </button>
            </div>

            <!-- Helper text -->
            <p class="text-center text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.auth.webauthn.supportedMethods') }}
            </p>
          </form>
        </div>

        <!-- Magic Link panel -->
        <form
          v-else-if="isMagicLinkTab(index)"
          @submit.prevent="handleMagicLinkSubmit"
          class="space-y-6"
          data-testid="magic-link-panel">
          <!-- Error message -->
          <div
            v-if="currentError"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert"
            aria-live="assertive"
            aria-atomic="true">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ currentError }}
            </p>
          </div>

          <!-- Email field -->
          <div>
            <label
              for="signin-email"
              class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.COMMON.field_email') }}
            </label>
            <input
              id="signin-email"
              name="email"
              type="email"
              autocomplete="email"
              required
              :disabled="isLoading"
              class="block w-full appearance-none rounded-md
                     border border-gray-300 px-3 py-2 text-lg
                     text-gray-900 placeholder:text-gray-500
                     focus:border-brand-500 focus:outline-none focus:ring-brand-500
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:border-gray-600 dark:bg-gray-700 dark:text-white
                     dark:placeholder:text-gray-400 dark:focus:border-brand-500
                     dark:focus:ring-brand-500"
              :placeholder="t('web.COMMON.email_placeholder')"
              v-model="email"
              data-testid="magic-link-email-input" />
          </div>

          <!-- Submit button -->
          <div>
            <button
              type="submit"
              :disabled="isLoading"
              class="group relative flex w-full justify-center rounded-md
                     border border-transparent bg-brand-600 px-4 py-2
                     text-lg font-medium text-white hover:bg-brand-700
                     focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800"
              data-testid="magic-link-submit">
              <span v-if="isLoading" class="flex items-center">
                <svg
                  class="-ml-1 mr-3 size-5 animate-spin text-white"
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
                {{ t('web.COMMON.processing') }}
              </span>
              <span v-else>{{ t('web.login.send_sign_in_link') }}</span>
            </button>
          </div>

          <!-- Helper text -->
          <p class="text-center text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.login.secure_link_helper') }}
          </p>
        </form>

        <!-- Password panel -->
        <form
          v-else-if="isPasswordTab(index)"
          @submit.prevent="handlePasswordSubmit"
          class="space-y-6"
          data-testid="password-panel">
          <!-- Lockout alert (takes precedence over generic error) -->
          <LockoutAlert :lockout="lockoutStatus" />

          <!-- Generic error message (shown when not a lockout error) -->
          <div
            v-if="currentError && !lockoutStatus"
            id="signin-error"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert"
            aria-live="assertive"
            aria-atomic="true">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ currentError }}
            </p>
          </div>

          <div class="space-y-4">
            <!-- Email field -->
            <div>
              <label
                for="signin-email-password"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.COMMON.field_email') }}
              </label>
              <input
                id="signin-email-password"
                name="email"
                type="email"
                autocomplete="email"
                required
                :disabled="isLoading"
                :aria-invalid="currentError && !lockoutStatus ? 'true' : undefined"
                :aria-describedby="currentError && !lockoutStatus ? 'signin-error' : undefined"
                class="block w-full appearance-none rounded-md
                       border border-gray-300 px-3 py-2 text-lg
                       text-gray-900 placeholder:text-gray-500
                       focus:border-brand-500 focus:outline-none focus:ring-brand-500
                       disabled:cursor-not-allowed disabled:opacity-50
                       dark:border-gray-600 dark:bg-gray-700 dark:text-white
                       dark:placeholder:text-gray-400 dark:focus:border-brand-500
                       dark:focus:ring-brand-500"
                :placeholder="t('web.COMMON.email_placeholder')"
                v-model="email"
                data-testid="password-email-input" />
            </div>

            <!-- Password input with visibility toggle -->
            <div>
              <label
                for="signin-password"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.COMMON.field_password') }}
              </label>
              <div class="relative">
                <input
                  id="signin-password"
                  :type="showPassword ? 'text' : 'password'"
                  name="password"
                  autocomplete="current-password"
                  required
                  :disabled="isLoading"
                  :aria-invalid="currentError && !lockoutStatus ? 'true' : undefined"
                  :aria-describedby="currentError && !lockoutStatus ? 'signin-error' : undefined"
                  class="block w-full appearance-none rounded-md
                         border border-gray-300 px-3 py-2 pr-10 text-lg
                         text-gray-900 placeholder:text-gray-500
                         focus:border-brand-500 focus:outline-none focus:ring-brand-500
                         disabled:cursor-not-allowed disabled:opacity-50
                         dark:border-gray-600 dark:bg-gray-700 dark:text-white
                         dark:placeholder:text-gray-400 dark:focus:border-brand-500
                         dark:focus:ring-brand-500"
                  :placeholder="t('web.COMMON.password_placeholder')"
                  v-model="password"
                  data-testid="password-input" />
                <button
                  type="button"
                  @click="togglePasswordVisibility"
                  :disabled="isLoading"
                  :aria-label="showPassword ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')"
                  class="absolute inset-y-0 right-0 z-10 flex cursor-pointer items-center pr-3 text-sm leading-5 disabled:opacity-50"
                  data-testid="toggle-password-visibility">
                  <OIcon
                    collection="heroicons"
                    :name="showPassword ? 'outline-eye-off' : 'solid-eye'"
                    size="5"
                    class="text-gray-400"
                    aria-hidden="true" />
                </button>
              </div>
            </div>
          </div>

          <!-- Remember me -->
          <div class="flex items-center">
            <input
              id="remember-me"
              name="remember-me"
              type="checkbox"
              :disabled="isLoading"
              aria-describedby="remember-me-description"
              class="size-4 rounded border-gray-300 text-brand-600
                     focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50
                     dark:border-gray-600 dark:bg-gray-700 dark:ring-offset-gray-800
                     dark:focus:ring-brand-500"
              v-model="rememberMe"
              data-testid="remember-me-checkbox" />
            <label
              for="remember-me"
              class="ml-2 block text-sm text-gray-900 dark:text-gray-300">
              {{ t('web.login.remember_me') }}
            </label>
            <span id="remember-me-description" class="sr-only">
              {{ t('web.COMMON.remember_me_description') }}
            </span>
          </div>

          <!-- Submit button -->
          <div>
            <button
              type="submit"
              :disabled="isLoading"
              class="group relative flex w-full justify-center rounded-md
                     border border-transparent bg-brand-600 px-4 py-2
                     text-lg font-medium text-white hover:bg-brand-700
                     focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800"
              data-testid="password-submit">
              <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
              <span v-else>{{ t('web.login.button_sign_in') }}</span>
            </button>
            <!-- Loading state announcement (screen reader only) -->
            <div
              v-if="isLoading"
              aria-live="polite"
              aria-atomic="true"
              class="sr-only">
              {{ t('web.COMMON.form_processing') }}
            </div>
          </div>
        </form>
      </TabPanel>
    </TabPanels>
  </TabGroup>
</template>
