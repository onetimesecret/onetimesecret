<!-- src/apps/session/components/PasswordlessFirstSignIn.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { TabGroup, TabList, Tab, TabPanels, TabPanel } from '@headlessui/vue';
import LockoutAlert from '@/apps/session/components/LockoutAlert.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { useMagicLink } from '@/shared/composables/useMagicLink';
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();

export interface Props {
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  locale: 'en',
});

const emit = defineEmits<{
  (e: 'mode-change', mode: 'passwordless' | 'password'): void;
}>();

type AuthMode = 'passwordless' | 'password';

// Tab index: 0 = Magic Link (default), 1 = Password
const selectedTabIndex = ref(0);

// Prefill email from query param (e.g., from invitation flow)
const emailFromQuery = typeof route.query.email === 'string' ? route.query.email : '';
const email = ref(emailFromQuery);

// Current mode derived from tab index
const currentMode = computed<AuthMode>(() =>
  selectedTabIndex.value === 0 ? 'passwordless' : 'password'
);

// Password mode state
const password = ref('');
const rememberMe = ref(false);
const showPassword = ref(false);

// Auth composables
const { login, isLoading: isPasswordLoading, error: passwordError, lockoutStatus, clearErrors } = useAuth();
const { requestMagicLink, sent: magicLinkSent, isLoading: isMagicLinkLoading, error: magicLinkError, clearState: clearMagicLinkState } = useMagicLink();

// Combined loading state
const isLoading = computed(() => isPasswordLoading.value || isMagicLinkLoading.value);

// Current error based on mode
const currentError = computed(() => {
  if (currentMode.value === 'password') {
    return passwordError.value;
  }
  return magicLinkError.value;
});

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

// Handle tab change from HeadlessUI
const handleTabChange = (index: number) => {
  selectedTabIndex.value = index;
  const mode: AuthMode = index === 0 ? 'passwordless' : 'password';

  if (mode === 'passwordless') {
    clearErrors();
    password.value = '';
  } else {
    clearMagicLinkState();
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

const handleTryAgain = () => {
  clearMagicLinkState();
  email.value = '';
};
</script>

<template>
  <!-- Magic link sent success state -->
  <div v-if="magicLinkSent" class="space-y-6">
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
      class="text-sm text-brand-600 transition duration-300 ease-in-out hover:underline dark:text-brand-400">
      {{ t('web.auth.magicLink.tryDifferentEmail') }}
    </button>
  </div>

  <!-- Main form with HeadlessUI tabs -->
  <TabGroup
    v-else
    :selected-index="selectedTabIndex"
    @change="handleTabChange"
    as="div"
    class="space-y-6">
    <!-- Tab list -->
    <TabList class="flex justify-center border-b border-gray-200 dark:border-gray-700">
      <Tab
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
          ]">
          {{ t('web.login.tab_magic_link') }}
          <span
            v-if="selected"
            class="absolute inset-x-0 -bottom-px h-0.5 bg-brand-500 dark:bg-brand-400"
            aria-hidden="true"></span>
        </button>
      </Tab>
      <Tab
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
          ]">
          {{ t('web.login.tab_password') }}
          <span
            v-if="selected"
            class="absolute inset-x-0 -bottom-px h-0.5 bg-brand-500 dark:bg-brand-400"
            aria-hidden="true"></span>
        </button>
      </Tab>
    </TabList>

    <!-- Tab panels -->
    <TabPanels>
      <!-- Magic Link panel (index 0, default) -->
      <TabPanel>
        <form
          @submit.prevent="handleMagicLinkSubmit"
          class="space-y-6">
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
              v-model="email" />
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
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
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
      </TabPanel>

      <!-- Password panel (index 1) -->
      <TabPanel>
        <form
          @submit.prevent="handlePasswordSubmit"
          class="space-y-6">
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
                v-model="email" />
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
                  v-model="password" />
                <button
                  type="button"
                  @click="togglePasswordVisibility"
                  :disabled="isLoading"
                  :aria-label="showPassword ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')"
                  class="absolute inset-y-0 right-0 z-10 flex cursor-pointer items-center pr-3 text-sm leading-5 disabled:opacity-50">
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
              v-model="rememberMe" />
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
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
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
