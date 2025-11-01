<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/MfaVerify.vue -->
<script setup lang="ts">
  import AuthView from '@/components/auth/AuthView.vue';
  import OtpCodeInput from '@/components/auth/OtpCodeInput.vue';
  import { useMfa } from '@/composables/useMfa';
  import { useAuth } from '@/composables/useAuth';
  import { useAuthStore } from '@/stores/authStore';
  import { ref, onMounted } from 'vue';
  import { useRouter } from 'vue-router';

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
    heading="Two-Factor Authentication"
    heading-id="mfa-verify-heading"
    :with-subheading="false">
    <template #form>
      <div class="mt-8 space-y-6">
        <!-- OTP Mode -->
        <div v-if="!useRecoveryMode">
          <p class="mb-6 text-center text-gray-600 dark:text-gray-400">
            {{ $t('web.auth.mfa.enter-code') }}
          </p>

          <!-- OTP Input -->
          <div class="mb-6">
            <OtpCodeInput
              ref="otpInputRef"
              :disabled="isLoading"
              @complete="handleOtpComplete" />
          </div>

          <!-- Error message -->
          <div
            v-if="error"
            class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ error }}
            </p>
          </div>

          <!-- Verify button -->
          <button
            @click="handleVerifyOtp"
            :disabled="otpCode.length !== 6 || isLoading"
            type="button"
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 mb-4">
            <span v-if="isLoading">{{ $t('web.COMMON.processing') || 'Processing...' }}</span>
            <span v-else>{{ $t('web.auth.mfa.verify') }}</span>
          </button>

          <!-- Switch to recovery code and cancel -->
          <div class="space-y-2 text-center">
            <button
              @click="toggleRecoveryMode"
              type="button"
              class="text-sm text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('web.auth.mfa.use-recovery-code') }}
            </button>
            <div class="pt-2">
              <button
                @click="handleCancel"
                type="button"
                :disabled="isLoading"
                class="w-full rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700">
                {{ $t('web.auth.mfa.cancel') }}
              </button>
            </div>
          </div>
        </div>

        <!-- Recovery Code Mode -->
        <div v-else>
          <p class="mb-6 text-center text-gray-600 dark:text-gray-400">
            Enter one of your recovery codes
          </p>

          <form
            @submit.prevent="handleRecoverySubmit"
            class="space-y-4">
            <!-- Recovery code input -->
            <div>
              <label
                for="recovery-code"
                class="sr-only"
                >Recovery Code</label
              >
              <input
                id="recovery-code"
                v-model="recoveryCode"
                type="text"
                :disabled="isLoading"
                placeholder="Enter recovery code"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500" />
            </div>

            <!-- Error message -->
            <div
              v-if="error"
              class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
              role="alert">
              <p class="text-sm text-red-800 dark:text-red-200">
                {{ error }}
              </p>
            </div>

            <!-- Submit button -->
            <button
              type="submit"
              :disabled="isLoading || !recoveryCode.trim()"
              class="w-full rounded-md bg-brand-600 px-4 py-2 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              <span v-if="isLoading">{{ $t('web.COMMON.processing') || 'Processing...' }}</span>
              <span v-else>Verify Recovery Code</span>
            </button>

            <!-- Switch back to OTP and cancel -->
            <div class="space-y-2 text-center">
              <button
                @click="toggleRecoveryMode"
                type="button"
                class="text-sm text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                {{ $t('web.auth.mfa.back-to-code') }}
              </button>
              <div class="pt-2">
                <button
                @click="handleCancel"
                type="button"
                :disabled="isLoading"
                class="w-full rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700">
                {{ $t('web.auth.mfa.cancel') }}
              </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </template>
  </AuthView>
</template>
