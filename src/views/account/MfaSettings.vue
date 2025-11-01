<script setup lang="ts">
  import OtpSetupWizard from '@/components/auth/OtpSetupWizard.vue';
  import SettingsLayout from '@/components/layout/SettingsLayout.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useAccount } from '@/composables/useAccount';
  import { useMfa } from '@/composables/useMfa';
  import { ref, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const { mfaStatus, isLoading, error, fetchMfaStatus, disableMfa, clearError } = useMfa();
  const { fetchAccountInfo } = useAccount();

  const showSetupWizard = ref(false);
  const showDisableConfirm = ref(false);
  const disablePassword = ref('');
  const isDisabling = ref(false);

  onMounted(async () => {
    await fetchMfaStatus();
  });

  // Start MFA setup
  const handleEnableMfa = () => {
    showSetupWizard.value = true;
  };

  // Complete MFA setup
  const handleSetupComplete = async () => {
    showSetupWizard.value = false;
    // Refresh MFA status and account info
    await fetchMfaStatus();
    await fetchAccountInfo();
  };

  // Cancel setup
  const handleSetupCancel = () => {
    showSetupWizard.value = false;
  };

  // Show disable confirmation
  const handleDisableClick = () => {
    clearError();
    disablePassword.value = '';
    showDisableConfirm.value = true;
  };

  // Disable MFA
  const handleDisableConfirm = async () => {
    if (!disablePassword.value) return;

    isDisabling.value = true;
    const success = await disableMfa(disablePassword.value);
    isDisabling.value = false;

    if (success) {
      showDisableConfirm.value = false;
      await fetchMfaStatus();
      await fetchAccountInfo();
    }
  };
</script>

<template>
  <SettingsLayout>
    <div>
      <div class="mb-6">
        <h1 class="text-3xl font-bold dark:text-white">
          {{ t('web.auth.mfa.title') }}
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          {{ t('web.auth.mfa.setup-description') }}
        </p>
      </div>

      <!-- Loading state -->
      <div
        v-if="isLoading && !mfaStatus"
        class="flex items-center justify-center py-12">
        <i class="fas fa-spinner fa-spin mr-2 text-2xl text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">{{ t('web.auth.mfa.loading-status') }}</span>
      </div>

      <!-- Error state -->
      <div
        v-else-if="error && !mfaStatus"
        class="rounded-lg bg-red-50 p-6 dark:bg-red-900/20"
        role="alert">
        <div class="flex items-center gap-3">
          <i class="fas fa-exclamation-circle text-2xl text-red-600 dark:text-red-400"></i>
          <div>
            <h3 class="font-semibold text-red-800 dark:text-red-200">{{ error }}</h3>
            <p class="mt-1 text-sm text-red-700 dark:text-red-300">{{ error }}</p>
            <button
              @click="fetchMfaStatus"
              type="button"
              class="mt-3 text-sm font-medium text-red-800 underline hover:text-red-900 dark:text-red-200 dark:hover:text-red-100">
              Try again
            </button>
          </div>
        </div>
      </div>

      <!-- Setup wizard (when enabling) -->
      <div
        v-else-if="showSetupWizard"
        class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <OtpSetupWizard
          @complete="handleSetupComplete"
          @cancel="handleSetupCancel" />
      </div>

      <!-- MFA Status (when not in setup) -->
      <div
        v-else-if="mfaStatus"
        class="space-y-6">
        <!-- MFA Enabled -->
        <div
          v-if="mfaStatus.enabled"
          class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center gap-3">
                <i class="fas fa-shield-check text-3xl text-green-500"></i>
                <div>
                  <h2 class="text-xl font-semibold dark:text-white">
                    {{ t('web.auth.mfa.enabled') }}
                  </h2>
                  <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                    {{ t('web.auth.mfa.protected-description') }}
                  </p>
                </div>
              </div>

              <!-- Last used -->
              <div
                v-if="mfaStatus.last_used_at"
                class="mt-4 text-sm text-gray-600 dark:text-gray-400">
                {{
                  t('web.auth.mfa.last-used', {
                    time: new Date(mfaStatus.last_used_at).toLocaleString(),
                  })
                }}
              </div>
              <div
                v-else
                class="mt-4 text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.auth.mfa.never-used') }}
              </div>

              <!-- Recovery codes status -->
              <div class="mt-4">
                <router-link
                  to="/account/settings/security/recovery-codes"
                  class="text-sm text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                  <i class="fas fa-key mr-1"></i>
                  {{
                    t('web.auth.recovery-codes.remaining', {
                      count: mfaStatus.recovery_codes_remaining,
                    })
                  }}
                </router-link>
              </div>
            </div>

            <!-- Disable button -->
            <button
              @click="handleDisableClick"
              type="button"
              class="rounded-md border border-red-300 px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:border-red-600 dark:text-red-400 dark:hover:bg-red-900/20">
              {{ t('web.auth.mfa.disable') }}
            </button>
          </div>
        </div>

        <!-- MFA Disabled -->
        <div
          v-else
          class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center gap-3">
                <i class="fas fa-shield-alt text-3xl text-gray-400"></i>
                <div>
                  <h2 class="text-xl font-semibold dark:text-white">
                    {{ t('web.auth.mfa.disabled') }}
                  </h2>
                  <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                    {{ t('web.auth.mfa.enable-description') }}
                  </p>
                </div>
              </div>

              <!-- Benefits list -->
              <ul class="mt-4 space-y-2 text-sm text-gray-600 dark:text-gray-400">
                <li class="flex items-center">
                  <i class="fas fa-check mr-2 text-green-500"></i>
                  {{ t('web.auth.mfa.benefit-unauthorized') }}
                </li>
                <li class="flex items-center">
                  <i class="fas fa-check mr-2 text-green-500"></i>
                  {{ t('web.auth.mfa.benefit-apps') }}
                </li>
                <li class="flex items-center">
                  <i class="fas fa-check mr-2 text-green-500"></i>
                  {{ t('web.auth.mfa.benefit-recovery') }}
                </li>
              </ul>
            </div>

            <!-- Enable button -->
            <button
              @click="handleEnableMfa"
              type="button"
              class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
              {{ t('web.auth.mfa.enable') }}
            </button>
          </div>
        </div>

        <!-- Quick links -->
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
          <h3
            class="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('web.LABELS.related-settings') }}
          </h3>
          <div class="space-y-2">
            <router-link
              to="/account/settings/security/recovery-codes"
              class="flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600 dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="key"
                class="w-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.recovery-codes.link-title') }}</span>
            </router-link>
            <router-link
              to="/account/settings/security/sessions"
              class="flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600 dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="computer-desktop-solid"
                class="w-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.sessions.link-title') }}</span>
            </router-link>
          </div>
        </div>
      </div>

      <!-- Disable confirmation modal -->
      <div
        v-if="showDisableConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
        @click.self="showDisableConfirm = false">
        <div
          class="mx-4 max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
          role="dialog"
          aria-modal="true"
          aria-labelledby="disable-mfa-title">
          <div class="mb-4 flex items-center">
            <i class="fas fa-exclamation-triangle mr-3 text-2xl text-yellow-500"></i>
            <h3
              id="disable-mfa-title"
              class="text-lg font-semibold dark:text-white">
              {{ t('web.auth.mfa.disable') }}
            </h3>
          </div>

          <p class="mb-4 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.auth.mfa.require-password') }}
          </p>

          <form @submit.prevent="handleDisableConfirm">
            <!-- Password input -->
            <div class="mb-4">
              <label
                for="disable-password"
                class="sr-only"
                >Password</label
              >
              <input
                id="disable-password"
                v-model="disablePassword"
                type="password"
                autocomplete="current-password"
                :disabled="isDisabling"
                :placeholder="t('web.auth.mfa.password-placeholder')"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
            </div>

            <!-- Error message -->
            <div
              v-if="error"
              class="mb-4 rounded-md bg-red-50 p-3 dark:bg-red-900/20"
              role="alert">
              <p class="text-sm text-red-800 dark:text-red-200">
                {{ error }}
              </p>
            </div>

            <!-- Action buttons -->
            <div class="flex justify-end gap-3">
              <button
                @click="showDisableConfirm = false"
                type="button"
                :disabled="isDisabling"
                class="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
                {{ t('web.COMMON.word_cancel') }}
              </button>
              <button
                type="submit"
                :disabled="isDisabling || !disablePassword"
                class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
                <span v-if="isDisabling">{{ t('web.auth.mfa.disabling') }}</span>
                <span v-else>{{ t('web.auth.mfa.disable-button') }}</span>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
