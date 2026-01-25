<!-- src/apps/workspace/account/settings/ChangeEmail.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { ref } from 'vue';

  const { t } = useI18n();

  const currentEmail = ref('user@example.com'); // TODO: Load from account info
  const newEmail = ref('');
  const password = ref('');
  const isLoading = ref(false);
  const showPassword = ref(false);
  const errorMessage = ref('');
  const successMessage = ref('');

  const isValidEmail = ref(true);

  const validateEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  };

  const handleEmailInput = () => {
    errorMessage.value = '';
    isValidEmail.value = !newEmail.value || validateEmail(newEmail.value);
  };

  const handleSubmit = async () => {
    errorMessage.value = '';
    successMessage.value = '';

    if (!newEmail.value || !password.value) {
      errorMessage.value = t('web.settings.profile.all_fields_required');
      return;
    }

    if (!validateEmail(newEmail.value)) {
      errorMessage.value = t('web.settings.profile.invalid_email');
      isValidEmail.value = false;
      return;
    }

    if (newEmail.value === currentEmail.value) {
      errorMessage.value = t('web.settings.profile.email_same_as_current');
      return;
    }

    isLoading.value = true;

    try {
      // TODO: Call API to change email
      console.log('Change email:', { newEmail: newEmail.value, password: password.value });

      // Simulate API call
      await new Promise(resolve => setTimeout(resolve, 1000));

      successMessage.value = t('web.settings.profile.email_change_success');
      currentEmail.value = newEmail.value;
      newEmail.value = '';
      password.value = '';
    } catch (error) {
      console.error('Error changing email:', error);
      errorMessage.value = t('web.settings.profile.email_change_error');
    } finally {
      isLoading.value = false;
    }
  };

  const togglePasswordVisibility = () => {
    showPassword.value = !showPassword.value;
  };
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Current Email -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="envelope"
              class="size-5 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('web.settings.profile.current_email') }}
            </h2>
          </div>
        </div>

        <div class="p-6">
          <div class="flex items-center gap-2">
            <p class="text-lg font-medium text-gray-900 dark:text-white">
              {{ currentEmail }}
            </p>
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-green-600 dark:text-green-400"
              aria-hidden="true" />
          </div>
        </div>
      </section>

      <!-- Change Email Form -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-start gap-3">
            <OIcon
              collection="heroicons"
              name="pencil-square"
              class="mt-0.5 size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <div class="min-w-0 flex-1">
              <h2 class="text-lg font-semibold leading-tight text-gray-900 dark:text-white">
                {{ t('web.settings.profile.change_email') }}
              </h2>
              <p class="mt-1 text-sm leading-tight text-gray-600 dark:text-gray-400">
                {{ t('web.settings.profile.change_email_description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6">
          <!-- Success Message -->
          <div
            v-if="successMessage"
            class="mb-6 rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-800 dark:bg-green-900/20">
            <div class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 shrink-0 text-green-600 dark:text-green-400"
                aria-hidden="true" />
              <p class="text-sm text-green-700 dark:text-green-300">
                {{ successMessage }}
              </p>
            </div>
          </div>

          <!-- Error Message -->
          <div
            v-if="errorMessage"
            class="mb-6 rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-800 dark:bg-red-900/20">
            <div class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="exclamation-circle-solid"
                class="size-5 shrink-0 text-red-600 dark:text-red-400"
                aria-hidden="true" />
              <p class="text-sm text-red-700 dark:text-red-300">
                {{ errorMessage }}
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
                class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.settings.profile.new_email') }}
              </label>
              <div class="relative mt-1">
                <input
                  id="new-email"
                  v-model="newEmail"
                  @input="handleEmailInput"
                  type="email"
                  autocomplete="email"
                  required
                  :class="[
                    'block w-full rounded-md border px-4 py-2.5 shadow-sm transition-colors',
                    'focus:outline-none focus:ring-2 focus:ring-brand-500',
                    !isValidEmail && newEmail
                      ? 'border-red-300 bg-red-50 text-red-900 focus:border-red-500 dark:border-red-700 dark:bg-red-900/20 dark:text-red-300'
                      : 'border-gray-300 bg-white text-gray-900 dark:border-gray-600 dark:bg-gray-800 dark:text-white',
                  ]" />
              </div>
              <p
                v-if="!isValidEmail && newEmail"
                class="mt-1 text-sm text-red-600 dark:text-red-400">
                {{ t('web.settings.profile.invalid_email') }}
              </p>
            </div>

            <!-- Password Confirmation -->
            <div>
              <label
                for="current-password"
                class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.settings.profile.current_password') }}
              </label>
              <div class="relative mt-1">
                <input
                  id="current-password"
                  v-model="password"
                  :type="showPassword ? 'text' : 'password'"
                  autocomplete="current-password"
                  required
                  class="block w-full rounded-md border border-gray-300 bg-white px-4 py-2.5 pr-10 text-gray-900 shadow-sm transition-colors focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
                <button
                  type="button"
                  @click="togglePasswordVisibility"
                  class="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                  :aria-label="showPassword ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')">
                  <OIcon
                    collection="heroicons"
                    :name="showPassword ? 'eye-slash-solid' : 'eye-solid'"
                    class="size-5"
                    aria-hidden="true" />
                </button>
              </div>
              <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.settings.profile.password_required_for_security') }}
              </p>
            </div>

            <!-- Submit Button -->
            <div class="flex flex-col items-start gap-4 border-t border-gray-200 pt-6 dark:border-gray-700 sm:flex-row sm:items-center sm:justify-between">
              <p class="text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.settings.profile.verification_email_notice') }}
              </p>
              <button
                type="submit"
                :disabled="isLoading || !newEmail || !password || !isValidEmail"
                :class="[
                  'inline-flex shrink-0 items-center gap-2 rounded-md px-6 py-2.5 text-sm font-medium shadow-sm transition-colors',
                  'focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2',
                  isLoading || !newEmail || !password || !isValidEmail
                    ? 'cursor-not-allowed bg-gray-300 text-gray-500 dark:bg-gray-700 dark:text-gray-400'
                    : 'bg-brand-600 text-white hover:bg-brand-700 dark:bg-brand-500 dark:hover:bg-brand-600',
                ]">
                <OIcon
                  v-if="isLoading"
                  collection="heroicons"
                  name="arrow-path-solid"
                  class="size-4 animate-spin"
                  aria-hidden="true" />
                {{ isLoading ? t('web.COMMON.processing') : t('web.settings.profile.update_email') }}
              </button>
            </div>
          </form>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
