<!-- src/apps/session/components/InviteSignInForm.vue -->
<!--
  Inline sign-in form for organization invitation flow.

  Unlike the main SignInForm, this component:
  - Has a readonly email field (prefilled from invitation)
  - Emits events instead of navigating
  - Handles MFA requirement by emitting mfaRequired event
  - Supports SSO/magic link buttons when auth methods are available
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { TabGroup, TabList, Tab, TabPanels, TabPanel } from '@headlessui/vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import SsoButton from '@/apps/session/components/SsoButton.vue';
import { useInviteAuth } from '@/apps/session/composables/useInviteAuth';
import { useMagicLink } from '@/shared/composables/useMagicLink';
import type { AuthMethod } from '@/schemas/api/invite/responses/show-invite';
import { ref, computed } from 'vue';

export interface Props {
  /**
   * Email address from the invitation - displayed readonly.
   */
  invitedEmail: string;
  /**
   * Invitation token for the accept flow.
   */
  inviteToken: string;
  /**
   * Organization name for context.
   */
  orgName: string;
  /**
   * Available authentication methods for this invitation.
   */
  authMethods?: AuthMethod[];
}

const props = withDefaults(defineProps<Props>(), {
  authMethods: () => [],
});

const emit = defineEmits<{
  (e: 'success'): void;
  (e: 'error', message: string): void;
  (e: 'mfaRequired', redirect: string): void;
  (e: 'decline'): void;
}>();

const { t } = useI18n();
const { loginAndAccept, isLoading, error, fieldErrors, clearErrors } = useInviteAuth();
const {
  requestMagicLink,
  sent: magicLinkSent,
  isLoading: isMagicLinkLoading,
  error: magicLinkError,
  clearState: clearMagicLinkState
} = useMagicLink();

const password = ref('');
const showPassword = ref(false);
const isSubmitting = ref(false);

/**
 * SSO auth method if available.
 */
const ssoMethod = computed(() =>
  props.authMethods?.find(m => m.type === 'sso' && m.enabled)
);

/**
 * Whether magic link auth is enabled.
 */
const hasMagicLink = computed(() =>
  props.authMethods?.some(m => m.type === 'magic_link' && m.enabled)
);

/**
 * Whether password auth is enabled.
 */
const passwordEnabled = computed(() => {
  const passwordMethod = props.authMethods?.find(m => m.type === 'password');
  // Default to enabled if no auth methods specified
  return !passwordMethod || passwordMethod.enabled;
});

/**
 * Tab configuration for auth methods.
 */
type AuthMode = 'password' | 'magic_link';

interface TabConfig {
  mode: AuthMode;
  labelKey: string;
}

const selectedTabIndex = ref(0);

const tabs = computed<TabConfig[]>(() => {
  const result: TabConfig[] = [];
  if (passwordEnabled.value) {
    result.push({ mode: 'password', labelKey: 'web.login.tab_password' });
  }
  if (hasMagicLink.value) {
    result.push({ mode: 'magic_link', labelKey: 'web.login.tab_magic_link' });
  }
  return result;
});

/**
 * Only show tabs if multiple auth methods are available.
 */
const showTabs = computed(() => tabs.value.length > 1);

/**
 * Current auth mode based on selected tab.
 */
const _currentMode = computed<AuthMode | null>(() => {
  if (tabs.value.length === 0) return null;
  return tabs.value[selectedTabIndex.value]?.mode ?? tabs.value[0]?.mode ?? null;
});

function handleTabChange(index: number) {
  selectedTabIndex.value = index;
  clearErrors();
  clearMagicLinkState();
}

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

/**
 * Sends a magic link to the invited email address.
 */
const handleMagicLinkRequest = async () => {
  await requestMagicLink(props.invitedEmail);
};

/**
 * Resets the magic link sent state for retry.
 */
const handleMagicLinkTryAgain = () => {
  clearMagicLinkState();
};

const handleSubmit = async () => {
  if (isSubmitting.value) return;

  isSubmitting.value = true;
  clearErrors();

  try {
    const result = await loginAndAccept(
      props.invitedEmail,
      password.value,
      props.inviteToken
    );

    if (result.success) {
      emit('success');
    } else if (result.requiresMfa && result.redirect) {
      emit('mfaRequired', result.redirect);
    } else if (result.error) {
      emit('error', result.error);
    }
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div class="mt-6 space-y-6">
    <!-- Magic link sent confirmation (shown outside tabs when sent) -->
    <div
      v-if="magicLinkSent"
      class="rounded-md bg-green-50 p-6 text-center dark:bg-green-900/20"
      data-testid="invite-signin-magic-link-sent">
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
        {{ t('web.auth.magicLink.sentTo', { email: invitedEmail }) }}
      </p>
      <p class="mt-3 text-xs text-green-700 dark:text-green-300">
        {{ t('web.auth.magicLink.linkExpiresIn') }}
      </p>
      <button
        type="button"
        @click="handleMagicLinkTryAgain"
        class="mt-4 text-sm text-brand-600 transition duration-300 ease-in-out hover:underline dark:text-brand-400"
        data-testid="invite-signin-magic-link-try-again">
        {{ t('web.auth.magicLink.tryDifferentEmail') }}
      </button>
    </div>

    <!-- Tabbed auth methods (when multiple methods available and magic link not sent) -->
    <TabGroup
      v-else-if="showTabs"
      :selected-index="selectedTabIndex"
      @change="handleTabChange"
      as="div"
      class="space-y-6"
      data-testid="invite-signin-auth-tabs">
      <!-- Tab list -->
      <TabList class="mb-6 flex justify-center border-b border-gray-200 dark:border-gray-700">
        <Tab
          v-for="tab in tabs"
          :key="tab.mode"
          v-slot="{ selected }"
          as="template">
          <button
            type="button"
            class="relative cursor-pointer px-5 py-3 text-base font-semibold transition-colors duration-200
                   focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2
                   dark:focus-visible:ring-offset-gray-800"
            :class="[
              selected
                ? 'text-brand-600 dark:text-brand-400'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
            ]"
            :data-testid="`invite-signin-tab-${tab.mode}`">
            {{ t(tab.labelKey) }}
            <span
              v-if="selected"
              class="absolute inset-x-0 -bottom-px h-0.5 bg-brand-600 dark:bg-brand-400"
              aria-hidden="true" ></span>
          </button>
        </Tab>
      </TabList>

      <!-- Tab panels -->
      <TabPanels>
        <!-- Password panel -->
        <TabPanel v-if="passwordEnabled" data-testid="invite-signin-password-panel">
          <form
            @submit.prevent="handleSubmit"
            data-testid="invite-signin-form">
            <!-- Error message -->
            <div
              v-if="error"
              id="signin-error"
              class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
              role="alert"
              aria-live="assertive"
              aria-atomic="true"
              data-testid="invite-signin-error">
              <div class="flex">
                <div class="shrink-0">
                  <svg
                    class="size-5 text-red-400"
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    aria-hidden="true">
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                      clip-rule="evenodd" />
                  </svg>
                </div>
                <div class="ml-3">
                  <div class="text-sm text-red-700 dark:text-red-300">
                    <p
                      v-if="fieldErrors.password"
                      class="font-medium">
                      {{ fieldErrors.password }}
                    </p>
                    <p
                      v-else-if="fieldErrors.login"
                      class="font-medium">
                      {{ fieldErrors.login }}
                    </p>
                    <p v-else>
                      {{ error }}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div class="space-y-4">
              <!-- Email field (readonly) -->
              <div>
                <label
                  for="invite-signin-email"
                  class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.COMMON.field_email') }}
                </label>
                <div class="relative">
                  <input
                    id="invite-signin-email"
                    name="email"
                    type="email"
                    autocomplete="email"
                    readonly
                    :value="invitedEmail"
                    class="block w-full appearance-none rounded-md
                           border border-gray-300
                           bg-gray-50 px-3
                           py-2 pr-10 text-lg
                           text-gray-600
                           dark:border-gray-600 dark:bg-gray-600 dark:text-gray-300"
                    data-testid="invite-signin-email-input" />
                  <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
                    <OIcon
                      collection="heroicons"
                      name="solid-lock-closed"
                      size="5"
                      class="text-gray-400"
                      aria-hidden="true" />
                  </div>
                </div>
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.invitations.email_locked_hint') }}
                </p>
              </div>

              <!-- Password field -->
              <div>
                <label
                  for="invite-signin-password"
                  class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.COMMON.field_password') }}
                </label>
                <div class="relative">
                  <input
                    id="invite-signin-password"
                    :type="showPassword ? 'text' : 'password'"
                    name="password"
                    autocomplete="current-password"
                    required
                    :disabled="isSubmitting || isLoading"
                    :aria-invalid="error ? 'true' : undefined"
                    :aria-describedby="error ? 'signin-error' : undefined"
                    class="block w-full appearance-none rounded-md
                           border border-gray-300
                           px-3 py-2 pr-10 text-lg
                           text-gray-900 placeholder:text-gray-500
                           focus:border-brand-500 focus:outline-none focus:ring-brand-500
                           disabled:cursor-not-allowed disabled:opacity-50
                           dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                           dark:focus:border-brand-500 dark:focus:ring-brand-500"
                    :placeholder="t('web.COMMON.password_placeholder')"
                    v-model="password"
                    @input="clearErrors"
                    data-testid="invite-signin-password-input" />
                  <button
                    type="button"
                    @click="togglePasswordVisibility"
                    :disabled="isSubmitting || isLoading"
                    :aria-label="showPassword ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')"
                    class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5 disabled:opacity-50"
                    data-testid="invite-signin-toggle-password">
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

            <!-- Forgot password link -->
            <div class="mt-3 flex justify-end">
              <router-link
                to="/forgot"
                class="text-sm text-gray-600 transition duration-300 ease-in-out hover:underline dark:text-gray-400"
                :aria-label="t('web.login.forgot_your_password')"
                data-testid="invite-signin-forgot-password">
                {{ t('web.login.forgot_your_password') }}
              </router-link>
            </div>

            <!-- Button row: Decline + Submit -->
            <div class="mt-5 flex gap-3">
              <!-- Decline button (ghost style) -->
              <button
                type="button"
                @click="emit('decline')"
                :disabled="isSubmitting || isLoading"
                class="flex-1 rounded-md border border-gray-300 bg-white px-4 py-2
                       text-sm font-medium text-gray-700 hover:bg-gray-50
                       disabled:cursor-not-allowed disabled:opacity-50
                       dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
                data-testid="invite-signin-decline">
                {{ t('web.organizations.invitations.decline') }}
              </button>

              <!-- Primary submit button (takes more space) -->
              <button
                type="submit"
                :disabled="isSubmitting || isLoading"
                class="flex-[2] rounded-md bg-brand-600 px-4 py-2
                       text-sm font-medium text-white hover:bg-brand-700
                       disabled:cursor-not-allowed disabled:opacity-50"
                data-testid="invite-signin-submit">
                <span v-if="isSubmitting || isLoading">{{ t('web.COMMON.processing') }}</span>
                <span v-else>{{ t('web.organizations.invitations.sign_in_and_accept') }}</span>
              </button>
            </div>
            <!-- Loading state announcement (screen reader only) -->
            <div
              v-if="isSubmitting || isLoading"
              aria-live="polite"
              aria-atomic="true"
              class="sr-only">
              {{ t('web.COMMON.form_processing') }}
            </div>
          </form>
        </TabPanel>

        <!-- Magic Link panel -->
        <TabPanel v-if="hasMagicLink" data-testid="invite-signin-magic-link-panel">
          <!-- Error message for magic link -->
          <div
            v-if="magicLinkError"
            class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert"
            data-testid="invite-signin-magic-link-error">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ magicLinkError }}
            </p>
          </div>

          <!-- Email display (readonly) -->
          <div class="mb-4">
            <label class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.COMMON.field_email') }}
            </label>
            <div class="relative">
              <input
                type="email"
                readonly
                :value="invitedEmail"
                class="block w-full appearance-none rounded-md
                       border border-gray-300
                       bg-gray-50 px-3
                       py-2 pr-10 text-lg
                       text-gray-600
                       dark:border-gray-600 dark:bg-gray-600 dark:text-gray-300"
                data-testid="invite-signin-magic-link-email" />
              <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
                <OIcon
                  collection="heroicons"
                  name="solid-lock-closed"
                  size="5"
                  class="text-gray-400"
                  aria-hidden="true" />
              </div>
            </div>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.invitations.email_locked_hint') }}
            </p>
          </div>

          <!-- Button row: Decline + Send link -->
          <div class="mt-5 flex gap-3">
            <!-- Decline button (ghost style) -->
            <button
              type="button"
              @click="emit('decline')"
              :disabled="isMagicLinkLoading"
              class="flex-1 rounded-md border border-gray-300 bg-white px-4 py-2
                     text-sm font-medium text-gray-700 hover:bg-gray-50
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
              data-testid="invite-signin-decline">
              {{ t('web.organizations.invitations.decline') }}
            </button>

            <!-- Magic link button -->
            <button
              type="button"
              :disabled="isMagicLinkLoading"
              @click="handleMagicLinkRequest"
              class="flex-[2] rounded-md bg-brand-600 px-4 py-2
                     text-sm font-medium text-white hover:bg-brand-700
                     disabled:cursor-not-allowed disabled:opacity-50"
              data-testid="invite-signin-magic-link-button">
              <span v-if="isMagicLinkLoading" class="flex items-center justify-center">
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
          <p class="mt-2 text-center text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.login.secure_link_helper') }}
          </p>
        </TabPanel>
      </TabPanels>
    </TabGroup>

    <!-- Single auth method (no tabs needed) -->
    <template v-else-if="!magicLinkSent">
      <!-- Password form only (when only password is available) -->
      <form
        v-if="passwordEnabled && !hasMagicLink"
        @submit.prevent="handleSubmit"
        data-testid="invite-signin-form">
        <!-- Error message -->
        <div
          v-if="error"
          id="signin-error"
          class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
          role="alert"
          aria-live="assertive"
          aria-atomic="true"
          data-testid="invite-signin-error">
          <div class="flex">
            <div class="shrink-0">
              <svg
                class="size-5 text-red-400"
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                aria-hidden="true">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                  clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <div class="text-sm text-red-700 dark:text-red-300">
                <p
                  v-if="fieldErrors.password"
                  class="font-medium">
                  {{ fieldErrors.password }}
                </p>
                <p
                  v-else-if="fieldErrors.login"
                  class="font-medium">
                  {{ fieldErrors.login }}
                </p>
                <p v-else>
                  {{ error }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-4">
          <!-- Email field (readonly) -->
          <div>
            <label
              for="invite-signin-email-single"
              class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.COMMON.field_email') }}
            </label>
            <div class="relative">
              <input
                id="invite-signin-email-single"
                name="email"
                type="email"
                autocomplete="email"
                readonly
                :value="invitedEmail"
                class="block w-full appearance-none rounded-md
                       border border-gray-300
                       bg-gray-50 px-3
                       py-2 pr-10 text-lg
                       text-gray-600
                       dark:border-gray-600 dark:bg-gray-600 dark:text-gray-300"
                data-testid="invite-signin-email-input" />
              <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
                <OIcon
                  collection="heroicons"
                  name="solid-lock-closed"
                  size="5"
                  class="text-gray-400"
                  aria-hidden="true" />
              </div>
            </div>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.invitations.email_locked_hint') }}
            </p>
          </div>

          <!-- Password field -->
          <div>
            <label
              for="invite-signin-password-single"
              class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.COMMON.field_password') }}
            </label>
            <div class="relative">
              <input
                id="invite-signin-password-single"
                :type="showPassword ? 'text' : 'password'"
                name="password"
                autocomplete="current-password"
                required
                :disabled="isSubmitting || isLoading"
                :aria-invalid="error ? 'true' : undefined"
                :aria-describedby="error ? 'signin-error' : undefined"
                class="block w-full appearance-none rounded-md
                       border border-gray-300
                       px-3 py-2 pr-10 text-lg
                       text-gray-900 placeholder:text-gray-500
                       focus:border-brand-500 focus:outline-none focus:ring-brand-500
                       disabled:cursor-not-allowed disabled:opacity-50
                       dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                       dark:focus:border-brand-500 dark:focus:ring-brand-500"
                :placeholder="t('web.COMMON.password_placeholder')"
                v-model="password"
                @input="clearErrors"
                data-testid="invite-signin-password-input" />
              <button
                type="button"
                @click="togglePasswordVisibility"
                :disabled="isSubmitting || isLoading"
                :aria-label="showPassword ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')"
                class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5 disabled:opacity-50"
                data-testid="invite-signin-toggle-password">
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

        <!-- Forgot password link -->
        <div class="mt-3 flex justify-end">
          <router-link
            to="/forgot"
            class="text-sm text-gray-600 transition duration-300 ease-in-out hover:underline dark:text-gray-400"
            :aria-label="t('web.login.forgot_your_password')"
            data-testid="invite-signin-forgot-password">
            {{ t('web.login.forgot_your_password') }}
          </router-link>
        </div>

        <!-- Button row: Decline + Submit -->
        <div class="mt-5 flex gap-3">
          <!-- Decline button (ghost style) -->
          <button
            type="button"
            @click="emit('decline')"
            :disabled="isSubmitting || isLoading"
            class="flex-1 rounded-md border border-gray-300 bg-white px-4 py-2
                   text-sm font-medium text-gray-700 hover:bg-gray-50
                   disabled:cursor-not-allowed disabled:opacity-50
                   dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
            data-testid="invite-signin-decline">
            {{ t('web.organizations.invitations.decline') }}
          </button>

          <!-- Primary submit button (takes more space) -->
          <button
            type="submit"
            :disabled="isSubmitting || isLoading"
            class="flex-[2] rounded-md bg-brand-600 px-4 py-2
                   text-sm font-medium text-white hover:bg-brand-700
                   disabled:cursor-not-allowed disabled:opacity-50"
            data-testid="invite-signin-submit">
            <span v-if="isSubmitting || isLoading">{{ t('web.COMMON.processing') }}</span>
            <span v-else>{{ t('web.organizations.invitations.sign_in_and_accept') }}</span>
          </button>
        </div>
        <!-- Loading state announcement (screen reader only) -->
        <div
          v-if="isSubmitting || isLoading"
          aria-live="polite"
          aria-atomic="true"
          class="sr-only">
          {{ t('web.COMMON.form_processing') }}
        </div>
      </form>

      <!-- Magic link only (when only magic link is available) -->
      <div v-else-if="hasMagicLink && !passwordEnabled">
        <!-- Error message for magic link -->
        <div
          v-if="magicLinkError"
          class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
          role="alert"
          data-testid="invite-signin-magic-link-error">
          <p class="text-sm text-red-800 dark:text-red-200">
            {{ magicLinkError }}
          </p>
        </div>

        <!-- Email display (readonly) -->
        <div class="mb-4">
          <label class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.COMMON.field_email') }}
          </label>
          <div class="relative">
            <input
              type="email"
              readonly
              :value="invitedEmail"
              class="block w-full appearance-none rounded-md
                     border border-gray-300
                     bg-gray-50 px-3
                     py-2 pr-10 text-lg
                     text-gray-600
                     dark:border-gray-600 dark:bg-gray-600 dark:text-gray-300"
              data-testid="invite-signin-magic-link-email" />
            <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
              <OIcon
                collection="heroicons"
                name="solid-lock-closed"
                size="5"
                class="text-gray-400"
                aria-hidden="true" />
            </div>
          </div>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.invitations.email_locked_hint') }}
          </p>
        </div>

        <!-- Button row: Decline + Send link -->
        <div class="mt-5 flex gap-3">
          <!-- Decline button (ghost style) -->
          <button
            type="button"
            @click="emit('decline')"
            :disabled="isMagicLinkLoading"
            class="flex-1 rounded-md border border-gray-300 bg-white px-4 py-2
                   text-sm font-medium text-gray-700 hover:bg-gray-50
                   disabled:cursor-not-allowed disabled:opacity-50
                   dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
            data-testid="invite-signin-decline">
            {{ t('web.organizations.invitations.decline') }}
          </button>

          <!-- Magic link button -->
          <button
            type="button"
            :disabled="isMagicLinkLoading"
            @click="handleMagicLinkRequest"
            class="flex-[2] rounded-md bg-brand-600 px-4 py-2
                   text-sm font-medium text-white hover:bg-brand-700
                   disabled:cursor-not-allowed disabled:opacity-50"
            data-testid="invite-signin-magic-link-button">
            <span v-if="isMagicLinkLoading" class="flex items-center justify-center">
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
        <p class="mt-2 text-center text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.login.secure_link_helper') }}
        </p>
      </div>
    </template>

    <!-- Divider when SSO is available (after password or magic link) -->
    <div
      v-if="ssoMethod && (passwordEnabled || hasMagicLink) && !magicLinkSent"
      class="relative">
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t border-gray-300 dark:border-gray-600"></div>
      </div>
      <div class="relative flex justify-center text-sm">
        <span class="bg-white px-2 text-gray-500 dark:bg-gray-800 dark:text-gray-400">
          {{ t('web.COMMON.or') }}
        </span>
      </div>
    </div>

    <!-- SSO Button when available -->
    <SsoButton
      v-if="ssoMethod && ssoMethod.type === 'sso' && ssoMethod.platform_route_name && !magicLinkSent"
      :route-name="ssoMethod.platform_route_name"
      :display-name="ssoMethod.display_name ?? undefined"
      :redirect="`/invite/${inviteToken}`" />
  </div>
</template>
