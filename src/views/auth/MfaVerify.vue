<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/MfaVerify.vue -->
<script setup lang="ts">
  import AuthView from '@/components/auth/AuthView.vue';
  import OtpCodeInput from '@/components/auth/OtpCodeInput.vue';
  import { useMfa } from '@/composables/useMfa';
  import { useAuthStore } from '@/stores/authStore';
  import { ref, onMounted } from 'vue';
  import { useRouter } from 'vue-router';

  const router = useRouter();
  const authStore = useAuthStore();
  const { verifyOtp, verifyRecoveryCode, requestMfaRecovery, isLoading, error, clearError } =
    useMfa();

  const otpCode = ref('');
  const recoveryCode = ref('');
  const useRecoveryMode = ref(false);
  const showRecoveryHelp = ref(false);
  const recoveryEmailSent = ref(false);
  const otpInputRef = ref<InstanceType | null>(null);

  // Check if user is already authenticated (shouldn't be here if so)
  onMounted(() => {
    if (authStore.isAuthenticated) {
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
      otpInputRef.value?.clear();
      otpCode.value = '';
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

  // Show recovery help section
  const toggleRecoveryHelp = () => {
    showRecoveryHelp.value = !showRecoveryHelp.value;
    clearError();
  };

  // Request MFA recovery email
  const handleMfaRecovery = async () => {
    clearError();
    const success = await requestMfaRecovery();

    if (success) {
      recoveryEmailSent.value = true;
    }
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

          <!-- Switch to recovery code -->
          <div class="space-y-2 text-center">
            <button
              @click="toggleRecoveryMode"
              type="button"
              class="text-sm text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('web.auth.mfa.use-recovery-code') }}
            </button>
            <div class="text-gray-500 dark:text-gray-500">or</div>
            <button
              @click="toggleRecoveryHelp"
              type="button"
              class="text-sm text-gray-600 transition-colors duration-200 hover:text-gray-500 dark:text-gray-400 dark:hover:text-gray-300">
              {{ $t('web.auth.mfa.cant-access-authenticator') }}
            </button>
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

            <!-- Switch back to OTP -->
            <div class="text-center">
              <button
                @click="toggleRecoveryMode"
                type="button"
                class="text-sm text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                {{ $t('web.auth.mfa.back-to-code') }}
              </button>
            </div>
          </form>
        </div>

        <!-- MFA Recovery Help Section -->
        <div
          v-if="showRecoveryHelp"
          class="mt-6 rounded-md bg-amber-50 p-4 dark:bg-amber-900/20">
          <div v-if="!recoveryEmailSent">
            <h3 class="dark:text-amber-200\ mb-2 text-sm font-medium text-amber-800">
              {{ $t('web.auth.mfa.recovery-help-title') }}
            </h3>
            <p class="dark:text-amber-300\ mb-4 text-sm text-amber-700">
              {{ $t('web.auth.mfa.recovery-help-text') }}
            </p>
            <button
              @click="handleMfaRecovery"
              :disabled="isLoading"
              class="dark:hover:bg-amber-600\ w-full rounded-md bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-700 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-700">
              <span v-if="isLoading">{{ $t('web.COMMON.processing') || 'Sending...' }}</span>
              <span v-else>{{ $t('web.auth.mfa.send-recovery-email') }}</span>
            </button>
            <button
              @click="toggleRecoveryHelp"
              type="button"
              class="dark:hover:text-amber-200\ mt-2 w-full text-sm text-amber-700 hover:text-amber-600 dark:text-amber-300">
              {{ $t('web.COMMON.cancel') || 'Cancel' }}
            </button>
          </div>
          <div
            v-else
            class="text-center">
            <div class="dark:text-green-200\ mb-2 text-green-800">
              <svg
                class="mx-auto h-12 w-12"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24\">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z\" />
              </svg>
            </div>
            <h3 class="dark:text-green-200\ mb-2 text-sm font-medium text-green-800">
              {{ $t('web.auth.mfa.recovery-email-sent-title') }}
            </h3>
            <p class="dark:text-green-300\ text-sm text-green-700">
              {{ $t('web.auth.mfa.recovery-email-sent-text') }}
            </p>
          </div>
        </div>
      </div>
    </template>
  </AuthView>
</template>
