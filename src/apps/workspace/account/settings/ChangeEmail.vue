<!-- src/apps/workspace/account/settings/ChangeEmail.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SettingsLayout
    from '@/apps/workspace/layouts/SettingsLayout.vue';
  import PasswordConfirmModal
    from '@/shared/components/modals/PasswordConfirmModal.vue';
  import { useAuth } from '@/shared/composables/useAuth';
  import {
    useBootstrapStore,
  } from '@/shared/stores/bootstrapStore';
  import { computed, ref } from 'vue';

  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();
  const {
    requestEmailChange,
    resendEmailChangeConfirmation,
    isLoading,
    error,
    fieldError,
    clearErrors,
  } = useAuth();

  const newEmail = ref('');
  const isValidEmail = ref(true);
  const successMessage = ref('');
  const showPasswordModal = ref(false);
  const isResending = ref(false);
  const resendSuccess = ref(false);

  const currentEmail = computed(
    () => bootstrapStore.email
  );

  const canSubmit = computed(
    () =>
      newEmail.value.length > 0 &&
      isValidEmail.value &&
      newEmail.value !== currentEmail.value &&
      !isLoading.value
  );

  const validateEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  };

  const handleEmailInput = () => {
    clearErrors();
    successMessage.value = '';
    isValidEmail.value =
      !newEmail.value || validateEmail(newEmail.value);
  };

  const handleSubmit = () => {
    clearErrors();
    successMessage.value = '';

    if (!newEmail.value) {
      return;
    }

    if (!validateEmail(newEmail.value)) {
      isValidEmail.value = false;
      return;
    }

    if (newEmail.value === currentEmail.value) {
      return;
    }

    showPasswordModal.value = true;
  };

  const handlePasswordConfirm = async (
    password: string
  ) => {
    const success = await requestEmailChange(
      newEmail.value,
      password
    );

    showPasswordModal.value = false;

    if (success) {
      successMessage.value = t(
        'web.settings.profile.email_change_success'
      );
      newEmail.value = '';
    }
  };

  const handlePasswordCancel = () => {
    showPasswordModal.value = false;
    clearErrors();
  };

  const handleResend = async () => {
    isResending.value = true;
    resendSuccess.value = false;
    clearErrors();

    const success =
      await resendEmailChangeConfirmation();

    isResending.value = false;

    if (success) {
      resendSuccess.value = true;
    }
  };
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Current Email -->
      <section
        class="rounded-lg border border-gray-200 bg-white
          dark:border-gray-700 dark:bg-gray-800">
        <div
          class="border-b border-gray-200 px-6 py-4
            dark:border-gray-700">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="envelope"
              class="size-5 text-gray-500
                dark:text-gray-400"
              aria-hidden="true" />
            <h2
              class="text-lg font-semibold text-gray-900
                dark:text-white">
              {{ t('web.settings.profile.current_email') }}
            </h2>
          </div>
        </div>

        <div class="p-6">
          <div class="flex items-center gap-2">
            <p
              class="text-lg font-medium text-gray-900
                dark:text-white">
              {{ currentEmail }}
            </p>
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-green-600
                dark:text-green-400"
              aria-hidden="true" />
          </div>
        </div>
      </section>

      <!-- Change Email Form -->
      <section
        class="rounded-lg border border-gray-200 bg-white
          dark:border-gray-700 dark:bg-gray-800">
        <div
          class="border-b border-gray-200 px-6 py-4
            dark:border-gray-700">
          <div class="flex items-start gap-3">
            <OIcon
              collection="heroicons"
              name="pencil-square"
              class="mt-0.5 size-5 shrink-0 text-gray-500
                dark:text-gray-400"
              aria-hidden="true" />
            <div class="min-w-0 flex-1">
              <h2
                class="text-lg font-semibold leading-tight
                  text-gray-900 dark:text-white">
                {{
                  t('web.settings.profile.change_email')
                }}
              </h2>
              <p
                class="mt-1 text-sm leading-tight
                  text-gray-600 dark:text-gray-400">
                {{
                  t(
                    'web.settings.profile.change_email_description'
                  )
                }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6">
          <!-- Success Message -->
          <div
            v-if="successMessage"
            class="mb-6 rounded-lg border border-green-200
              bg-green-50 p-4 dark:border-green-800
              dark:bg-green-900/20">
            <div class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 shrink-0 text-green-600
                  dark:text-green-400"
                aria-hidden="true" />
              <div class="flex-1">
                <p
                  class="text-sm text-green-700
                    dark:text-green-300">
                  {{ successMessage }}
                </p>
                <p
                  v-if="resendSuccess"
                  class="mt-2 text-sm text-green-700
                    dark:text-green-300">
                  {{
                    t(
                      'web.settings.profile.resend_confirmation_success'
                    )
                  }}
                </p>
                <div class="mt-3 flex items-center gap-2">
                  <span
                    class="text-sm text-green-600
                      dark:text-green-400">
                    {{
                      t(
                        'web.settings.profile.didnt_receive_email'
                      )
                    }}
                  </span>
                  <button
                    type="button"
                    :disabled="isResending"
                    class="text-sm font-medium
                      text-brand-600 underline
                      hover:text-brand-700
                      disabled:cursor-not-allowed
                      disabled:opacity-50
                      dark:text-brand-400
                      dark:hover:text-brand-300"
                    @click="handleResend">
                    {{
                      isResending
                        ? t(
                          'web.settings.profile.resend_confirmation_sending'
                        )
                        : t(
                          'web.settings.profile.resend_confirmation'
                        )
                    }}
                  </button>
                </div>
                <p
                  v-if="error && !fieldError"
                  class="mt-2 text-sm text-red-600
                    dark:text-red-400">
                  {{ error }}
                </p>
              </div>
            </div>
          </div>

          <!-- Error Message -->
          <div
            v-if="error && fieldError?.[0] !== 'new_email'"
            class="mb-6 rounded-lg border border-red-200
              bg-red-50 p-4 dark:border-red-800
              dark:bg-red-900/20"
            role="alert">
            <div class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="exclamation-circle-solid"
                class="size-5 shrink-0 text-red-600
                  dark:text-red-400"
                aria-hidden="true" />
              <p
                class="text-sm text-red-700
                  dark:text-red-300">
                {{ error }}
              </p>
            </div>
          </div>

          <form
            @submit.prevent="handleSubmit"
            class="space-y-6">
            <!-- New Email -->
            <div>
              <label
                for="new-email"
                class="block text-sm font-medium
                  text-gray-700 dark:text-gray-300">
                {{ t('web.settings.profile.new_email') }}
              </label>
              <div class="relative mt-1">
                <input
                  id="new-email"
                  v-model="newEmail"
                  type="email"
                  autocomplete="email"
                  required
                  :disabled="isLoading"
                  :aria-invalid="
                    (!isValidEmail && newEmail)
                      || fieldError?.[0] === 'new_email'
                      ? 'true'
                      : undefined
                  "
                  :aria-describedby="
                    fieldError?.[0] === 'new_email'
                      ? 'new-email-error'
                      : undefined
                  "
                  :class="[
                    'block w-full rounded-md border',
                    'px-4 py-2.5 shadow-sm',
                    'transition-colors',
                    'focus:outline-none',
                    'focus:ring-2 focus:ring-brand-500',
                    'disabled:cursor-not-allowed',
                    'disabled:opacity-50',
                    (!isValidEmail && newEmail)
                      || fieldError?.[0] === 'new_email'
                      ? [
                          'border-red-300 bg-red-50',
                          'text-red-900',
                          'focus:border-red-500',
                          'dark:border-red-700',
                          'dark:bg-red-900/20',
                          'dark:text-red-300',
                        ]
                      : [
                          'border-gray-300 bg-white',
                          'text-gray-900',
                          'dark:border-gray-600',
                          'dark:bg-gray-800',
                          'dark:text-white',
                        ],
                  ]"
                  @input="handleEmailInput" />
              </div>
              <p
                v-if="!isValidEmail && newEmail"
                class="mt-1 text-sm text-red-600
                  dark:text-red-400">
                {{
                  t('web.settings.profile.invalid_email')
                }}
              </p>
              <p
                v-else-if="fieldError?.[0] === 'new_email'"
                id="new-email-error"
                role="alert"
                class="mt-2 text-sm text-red-600
                  dark:text-red-400">
                {{ fieldError[1] }}
              </p>
            </div>

            <!-- Submit Button -->
            <div
              class="flex flex-col items-start gap-4
                border-t border-gray-200 pt-6
                dark:border-gray-700
                sm:flex-row sm:items-center
                sm:justify-between">
              <p
                class="text-sm text-gray-600
                  dark:text-gray-400">
                {{
                  t(
                    'web.settings.profile.verification_email_notice'
                  )
                }}
              </p>
              <button
                type="submit"
                :disabled="!canSubmit"
                :class="[
                  'inline-flex shrink-0 items-center',
                  'gap-2 rounded-md px-6 py-2.5',
                  'text-sm font-medium shadow-sm',
                  'transition-colors',
                  'focus:outline-none focus:ring-2',
                  'focus:ring-brand-500',
                  'focus:ring-offset-2',
                  !canSubmit
                    ? [
                        'cursor-not-allowed bg-gray-300',
                        'text-gray-500',
                        'dark:bg-gray-700',
                        'dark:text-gray-400',
                      ]
                    : [
                        'bg-brand-600 text-white',
                        'hover:bg-brand-700',
                        'dark:bg-brand-500',
                        'dark:hover:bg-brand-600',
                      ],
                ]">
                <OIcon
                  v-if="isLoading"
                  collection="heroicons"
                  name="arrow-path-solid"
                  class="size-4 animate-spin"
                  aria-hidden="true" />
                {{
                  isLoading
                    ? t('web.COMMON.processing')
                    : t(
                      'web.settings.profile.update_email'
                    )
                }}
              </button>
            </div>
          </form>
        </div>
      </section>
    </div>

    <!-- Password Confirmation Modal -->
    <PasswordConfirmModal
      :open="showPasswordModal"
      :title="
        t('web.account.confirm_with_your_password')
      "
      :description="
        t(
          'web.settings.profile.password_required_for_security'
        )
      "
      :loading="isLoading"
      :error="
        fieldError?.[0] === 'password'
          ? fieldError[1]
          : null
      "
      @update:open="showPasswordModal = $event"
      @confirm="handlePasswordConfirm"
      @cancel="handlePasswordCancel" />
  </SettingsLayout>
</template>
