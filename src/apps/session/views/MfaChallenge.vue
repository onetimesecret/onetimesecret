<!-- src/apps/session/views/MfaChallenge.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import AuthView from '@/apps/session/components/AuthView.vue';
  import OtpCodeInput from '@/apps/session/components/OtpCodeInput.vue';
  import { loggingService } from '@/services/logging.service';
  import { useAuth } from '@/shared/composables/useAuth';
  import { useMfa } from '@/shared/composables/useMfa';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { ref, onMounted, computed } from 'vue';
  import { useRoute, useRouter } from 'vue-router';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();

  /**
   * Gets the redirect path from query params if valid.
   * Security: Only allows internal paths to prevent open redirect attacks.
   */
  const redirectPath = computed(() => {
    const redirect = route.query.redirect;
    if (typeof redirect !== 'string') return null;
    // Security: prevent open redirect attacks
    if (!redirect.startsWith('/') || redirect.startsWith('//') || redirect.includes('://')) {
      return null;
    }
    return redirect;
  });
  const authStore = useAuthStore();
  const { verifyOtp, verifyRecoveryCode, fetchMfaStatus, isLoading, error, clearError } = useMfa();
  const { logout } = useAuth();

  const otpCode = ref('');
  const recoveryCode = ref('');
  const useRecoveryMode = ref(false);
  const otpInputRef = ref<HTMLInputElement | null>(null);

  // Check if user is already fully authenticated or MFA is not enabled
  onMounted(async () => {
    loggingService.debug('[MfaChallenge] onMounted - checking state:', {
      isAuthenticated: authStore.isAuthenticated,
      isFullyAuthenticated: authStore.isFullyAuthenticated,
      awaitingMfa: authStore.awaitingMfa,
    });

    // Only redirect if FULLY authenticated (not just partially with MFA pending)
    if (authStore.isFullyAuthenticated) {
      loggingService.debug('[MfaChallenge] Already fully authenticated, redirecting to /');
      router.push('/');
      return;
    }

    // Check if MFA is actually enabled for this account
    const status = await fetchMfaStatus();
    loggingService.debug('[MfaChallenge] MFA status check:', { status });
    if (status && !status.enabled) {
      // MFA not enabled but session has awaiting_mfa=true
      // This is an inconsistent state - clear it by completing auth
      loggingService.debug('[MfaChallenge] MFA not enabled, completing auth');
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

    loggingService.debug('[MfaChallenge] Verifying OTP...');
    clearError();
    const success = await verifyOtp(otpCode.value);
    loggingService.debug('[MfaChallenge] OTP verification result:', { success });

    if (success) {
      // Update auth state and navigate
      loggingService.debug('[MfaChallenge] Setting authenticated=true');
      await authStore.setAuthenticated(true);
      loggingService.debug('[MfaChallenge] After setAuthenticated - auth complete');
      // Redirect to saved path or dashboard
      const destination = redirectPath.value || '/';
      loggingService.debug('[MfaChallenge] Redirecting to', { destination });
      router.push(destination);
    } else {
      // Clear input on error
      loggingService.debug('[MfaChallenge] OTP failed, clearing input');
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
      // Redirect to saved path or dashboard
      const destination = redirectPath.value || '/';
      router.push(destination);
    } else {
      // Clear input on error
      recoveryCode.value = '';
    }
  };

  // Handle cancel - logout and return to signin
  const handleCancel = async () => {
    clearError();
    // Pass the redirect URL to logout - it handles the navigation via window.location.href
    await logout('/signin');
    // No router.push needed - logout handles the redirect
  };
</script>

<template>
  <AuthView
    :heading="t('web.auth.mfa.title')"
    heading-id="mfa-verify-heading"
    :with-subheading="false"
    :show-return-home="false">
    <template #form>
      <div class="space-y-6">
        <!-- OTP Mode -->
        <div v-if="!useRecoveryMode">
          <p id="otp-instructions" class="mb-4 text-center text-gray-600 dark:text-gray-400">
            {{ t('web.auth.mfa.enter_code') }}
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
            {{ t('web.auth.mfa.otp_mode_active') }}
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
            <span v-else>{{ t('web.auth.mfa.verify_login') }}</span>
          </button>
          <span id="verify-button-hint" class="sr-only">
            {{ otpCode.length === 6 ? '' : t('web.auth.mfa.enter_all_digits') }}
          </span>

          <!-- Loading state announcement (screen reader only) -->
          <div
            v-if="isLoading"
            aria-live="polite"
            aria-atomic="true"
            class="sr-only">
            {{ t('web.COMMON.form_processing') }}
          </div>
        </div>

        <!-- Recovery Code Mode -->
        <div v-else>
          <!-- Mode announcement (screen reader only) -->
          <div aria-live="polite" class="sr-only">
            {{ t('web.auth.mfa.recovery_code_mode_active') }}
          </div>

          <p class="mb-4 text-center text-gray-600 dark:text-gray-400">
            {{ t('web.auth.mfa.enter_recovery_code') }}
          </p>

          <form
            @submit.prevent="handleRecoverySubmit"
            class="space-y-4">
            <!-- Recovery code input -->
            <div>
              <label
                for="recovery-code"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">{{ t('web.auth.mfa.recovery_code_label') }}</label>
              <input
                id="recovery-code"
                v-model="recoveryCode"
                type="text"
                :disabled="isLoading"
                :aria-invalid="error ? 'true' : undefined"
                :aria-describedby="error ? 'recovery-code-error' : undefined"
                :placeholder="t('web.auth.mfa.recovery_code_placeholder')"
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
              <span v-else>{{ t('web.auth.mfa.verify_recovery_code') }}</span>
            </button>

            <!-- Loading state announcement (screen reader only) -->
            <div
              v-if="isLoading"
              aria-live="polite"
              aria-atomic="true"
              class="sr-only">
              {{ t('web.COMMON.form_processing') }}
            </div>
          </form>
        </div>
      </div>
    </template>

    <!-- Footer: Secondary actions outside the card -->
    <template #footer>
      <div class="border-t border-gray-200 pt-4 dark:border-gray-700">
        <nav
          aria-label="Alternative authentication options"
          class="flex items-center justify-center gap-2 text-sm">
        <!-- OTP mode: show recovery code option -->
        <template v-if="!useRecoveryMode">
          <button
            @click="toggleRecoveryMode"
            type="button"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.auth.mfa.use_recovery_code_short') }}
          </button>
        </template>
        <!-- Recovery mode: show back to OTP option -->
        <template v-else>
          <button
            @click="toggleRecoveryMode"
            type="button"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.auth.mfa.back_to_code') }}
          </button>
        </template>

        <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>

        <button
          @click="handleCancel"
          type="button"
          :disabled="isLoading"
          class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400 dark:hover:text-gray-300">
          {{ t('web.auth.mfa.cancel_sign_in') }}
        </button>
        </nav>
      </div>
    </template>
  </AuthView>
</template>
