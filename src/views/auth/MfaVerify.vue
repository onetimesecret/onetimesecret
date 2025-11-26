<!-- src/views/auth/MfaVerify.vue -->
<script setup lang="ts">
  import AuthView from '@/components/auth/AuthView.vue';
  import OtpCodeInput from '@/components/auth/OtpCodeInput.vue';
  import { useAuth } from '@/composables/useAuth';
  import { useMfa } from '@/composables/useMfa';
  import { useAuthStore } from '@/stores/authStore';
  import { ref, onMounted } from 'vue';
  import { useRouter } from 'vue-router';

  const { t } = useI18n();
  const router = useRouter();
  const authStore = useAuthStore();
  const { verifyOtp, verifyRecoveryCode, fetchMfaStatus, isLoading, error, clearError } = useMfa();
  const { logout } = useAuth();

  const otpCode = ref('');
  const recoveryCode = ref('');
  const useRecoveryMode = ref(false);
  const otpInputRef = ref<HTMLInputElement | null>(null);

  // Check if user is already authenticated or MFA is not enabled
  onMounted(async () => {
    if (authStore.isAuthenticated) {
      router.push('/');
      return;
    }

    // Check if MFA is actually enabled for this account
    const status = await fetchMfaStatus();
    if (status && !status.enabled) {
      // MFA not enabled but session has awaiting_mfa=true
      // This is an inconsistent state - clear it by completing auth
      await authStore.setAuthenticated(true);
      router.push('/');
    }
  });

  // Handle OTP code complete
  const handleOtpComplete = async (code: string) => {
    otpCode.value = code;
    await handleVerifyOtp();
  };

  // Verify OTP code
  const handleVerifyOtp = async () => {
    if (otpCode.value.length !== 6) return;

    clearError();
    const success = await verifyOtp(otpCode.value);

    if (success) {
      // Update auth state and navigate
      await authStore.setAuthenticated(true);
      router.push('/');
    } else {
      // Clear input on error
      otpCode.value = '';
      if (otpInputRef.value) {
        otpInputRef.value.value = '';
        otpInputRef.value.focus();
      }
    }
  };

  // Toggle recovery code mode
  const toggleRecoveryMode = () => {
    useRecoveryMode.value = !useRecoveryMode.value;
    clearError();
    otpCode.value = '';
    recoveryCode.value = '';

    if (!useRecoveryMode.value) {
      // Focus OTP input when switching back
      setTimeout(() => otpInputRef.value?.focus(), 100);
    }
  };

  // Handle recovery code submission
  const handleRecoverySubmit = async () => {
    if (!recoveryCode.value.trim()) return;

    clearError();
    const success = await verifyRecoveryCode(recoveryCode.value.trim());

    if (success) {
      // Update auth state and navigate
      await authStore.setAuthenticated(true);
      router.push('/');
    } else {
      // Clear input on error
      recoveryCode.value = '';
    }
  };

  // Handle cancel - logout and return to signin
  const handleCancel = async () => {
    clearError();
    await logout();
    await authStore.setAuthenticated(false);
    router.push('/signin');
  };
</script>

<template>
  <AuthView
    :heading="t('web.auth.mfa.title')"
    heading-id="mfa-verify-heading"
    :with-subheading="false">
    <template #form>
      <div class="space-y-6">
        <!-- OTP Mode -->
        <div v-if="!useRecoveryMode">
          <p id="otp-instructions" class="mb-4 text-center text-gray-600 dark:text-gray-400">
            {{ t('web.auth.mfa.enter-code') }}
          </p>

          <!-- OTP Input -->
          <div class="mb-5">
            <OtpCodeInput
              ref="otpInputRef"
              :disabled="isLoading"
              :aria-describedby="error ? 'otp-error' : 'otp-instructions'"
              @complete="handleOtpComplete" />
          </div>

          <!-- Mode announcement (screen reader only) -->
          <div aria-live="polite" class="sr-only">
            {{ t('web.auth.mfa.otp-mode-active') }}
          </div>

          <!-- Error message -->
          <div
            v-if="error"
            id="otp-error"
            class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert"
            aria-live="assertive"
            aria-atomic="true">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ error }}
            </p>
          </div>

          <!-- Verify button -->
          <button
            @click="handleVerifyOtp"
            :disabled="otpCode.length !== 6 || isLoading"
            :aria-disabled="otpCode.length !== 6 || isLoading ? 'true' : undefined"
            aria-describedby="verify-button-hint"
            type="button"
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
            <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
            <span v-else>{{ t('web.auth.mfa.verify') }}</span>
          </button>
          <span id="verify-button-hint" class="sr-only">
            {{ otpCode.length === 6 ? '' : t('web.auth.mfa.enter-all-digits') }}
          </span>

          <!-- Loading state announcement (screen reader only) -->
          <div
            v-if="isLoading"
            aria-live="polite"
            aria-atomic="true"
            class="sr-only">
            {{ t('web.COMMON.form-processing') }}
          </div>

          <!-- Switch to recovery code and cancel -->
          <div class="mt-4 space-y-2 text-center">
            <button
              @click="toggleRecoveryMode"
              type="button"
              class="text-sm text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
              {{ t('web.auth.mfa.use-recovery-code') }}
            </button>
            <div class="mt-3">
              <button
                @click="handleCancel"
                type="button"
                :disabled="isLoading"
                :aria-label="t('web.auth.mfa.cancel') + ' - ' + t('web.login.button_sign_in')"
                class="w-full rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700">
                {{ t('web.auth.mfa.cancel') }}
              </button>
            </div>
          </div>
        </div>

        <!-- Recovery Code Mode -->
        <div v-else>
          <!-- Mode announcement (screen reader only) -->
          <div aria-live="polite" class="sr-only">
            {{ t('web.auth.mfa.recovery-code-mode-active') }}
          </div>

          <p class="mb-4 text-center text-gray-600 dark:text-gray-400">
            {{ t('web.auth.mfa.enter-recovery-code') }}
          </p>

          <form
            @submit.prevent="handleRecoverySubmit"
            class="space-y-4">
            <!-- Recovery code input -->
            <div>
              <label
                for="recovery-code"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">{{ t('web.auth.mfa.recovery-code-label') }}</label>
              <input
                id="recovery-code"
                v-model="recoveryCode"
                type="text"
                :disabled="isLoading"
                :aria-invalid="error ? 'true' : undefined"
                :aria-describedby="error ? 'recovery-code-error' : undefined"
                :placeholder="t('web.auth.mfa.recovery-code-placeholder')"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500" />
            </div>

            <!-- Error message -->
            <div
              v-if="error"
              id="recovery-code-error"
              class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
              role="alert"
              aria-live="assertive"
              aria-atomic="true">
              <p class="text-sm text-red-800 dark:text-red-200">
                {{ error }}
              </p>
            </div>

            <!-- Submit button -->
            <button
              type="submit"
              :disabled="isLoading || !recoveryCode.trim()"
              class="w-full rounded-md bg-brand-600 px-4 py-2 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
              <span v-else>{{ t('web.auth.mfa.verify-recovery-code') }}</span>
            </button>

            <!-- Loading state announcement (screen reader only) -->
            <div
              v-if="isLoading"
              aria-live="polite"
              aria-atomic="true"
              class="sr-only">
              {{ t('web.COMMON.form-processing') }}
            </div>

            <!-- Switch back to OTP and cancel -->
            <div class="space-y-2 text-center">
              <button
                @click="toggleRecoveryMode"
                type="button"
                class="text-sm text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                {{ t('web.auth.mfa.back-to-code') }}
              </button>
              <div class="mt-3">
                <button
                  @click="handleCancel"
                  type="button"
                  :disabled="isLoading"
                  class="w-full rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700">
                  {{ t('web.auth.mfa.cancel') }}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </template>
  </AuthView>
</template>
