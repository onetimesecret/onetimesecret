<!-- src/apps/session/views/MfaChallenge.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import AuthView from '@/apps/session/components/AuthView.vue';
  import OtpCodeInput from '@/apps/session/components/OtpCodeInput.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { loggingService } from '@/services/logging.service';
  import { useAuth } from '@/shared/composables/useAuth';
  import { useMfa } from '@/shared/composables/useMfa';
  import { useWebAuthn } from '@/shared/composables/useWebAuthn';
  import { useAuthStore } from '@/shared/stores/authStore';
  import type { MfaStatus } from '@/types/auth';
  import { isValidInternalPath } from '@/utils/redirect';
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
    return isValidInternalPath(redirect) ? redirect : null;
  });
  const authStore = useAuthStore();
  const { verifyOtp, verifyRecoveryCode, fetchMfaStatus, isLoading, error, clearError } = useMfa();
  const {
    supported: webauthnSupported,
    isLoading: webauthnLoading,
    error: webauthnError,
    verifyWebAuthnMfa,
    clearError: clearWebAuthnError,
  } = useWebAuthn();
  const { logout } = useAuth();

  /**
   * Which second factor the challenge currently collects. Replaces the old
   * useRecoveryMode boolean now that webauthn is a third option.
   */
  type ChallengeMode = 'otp' | 'recovery' | 'webauthn';

  const otpCode = ref('');
  const recoveryCode = ref('');
  const mode = ref<ChallengeMode>('otp');
  /**
   * Mode selected from the fetched status on mount. The recovery panel's back
   * link returns here — hardcoding 'otp' would strand webauthn-only accounts
   * on a code input they can never satisfy. May itself be 'recovery' when
   * recovery codes are the only completable factor (webauthn-only account on
   * an unsupported browser); the recovery panel then renders no back link.
   */
  const initialMode = ref<ChallengeMode>('otp');
  const mfaStatus = ref<MfaStatus | null>(null);
  const otpInputRef = ref<HTMLInputElement | null>(null);

  // Per-factor flags. The additive status fields are optional (older backends
  // omit them) — undefined is treated as false everywhere.
  const otpEnabled = computed(() => mfaStatus.value?.otp_enabled === true);
  const webauthnEnabled = computed(() => mfaStatus.value?.webauthn_enabled === true);
  const hasRecoveryCodes = computed(() => (mfaStatus.value?.recovery_codes_remaining ?? 0) > 0);
  /** WebAuthn is only offerable when the account has it AND the browser can do it. */
  const webauthnOffered = computed(() => webauthnEnabled.value && webauthnSupported.value);
  /**
   * Terminal state: the account's ONLY completable factor is webauthn but the
   * browser cannot perform the ceremony (webviews, old Safari, non-secure
   * contexts). Rendering any factor panel here would dead-end — the OTP input
   * and recovery form can never be satisfied — so an explicit
   * unsupported-browser notice replaces them, leaving Cancel as the exit.
   */
  const webauthnUnsupported = computed(
    () =>
      webauthnEnabled.value &&
      !otpEnabled.value &&
      !hasRecoveryCodes.value &&
      !webauthnSupported.value
  );

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
    mfaStatus.value = status;
    // `enabled` means otp || recovery ONLY — a webauthn-only account reports
    // enabled=false, so the guard must also check webauthn_enabled or it would
    // kick those accounts straight past the challenge.
    if (status && !status.enabled && !status.webauthn_enabled) {
      // MFA not enabled but session has awaiting_mfa=true
      // This is an inconsistent state - clear it by completing auth
      loggingService.debug('[MfaChallenge] MFA not enabled, completing auth');
      await authStore.setAuthenticated(true);
      router.push('/');
      return;
    }

    if (status) {
      // OTP wins when present (today's default); webauthn leads only when it
      // is the sole usable factor. When webauthn is unusable in this browser
      // but recovery codes remain, recovery is the only completable factor,
      // so start there (webauthn_enabled implies a new backend, so this can
      // never fire for legacy responses). The final 'otp' fallback preserves
      // the pre-additive-fields behavior against older backends; the
      // no-completable-factor case renders the webauthnUnsupported notice
      // instead of whatever mode is set here.
      if (status.otp_enabled) {
        initialMode.value = 'otp';
      } else if (status.webauthn_enabled && webauthnSupported.value) {
        initialMode.value = 'webauthn';
      } else if (status.webauthn_enabled && hasRecoveryCodes.value) {
        initialMode.value = 'recovery';
      } else {
        initialMode.value = 'otp';
      }
      mode.value = initialMode.value;
    }
  });

  /**
   * Shared success epilogue: complete auth, then honor the validated redirect.
   * All three factors converge here so their post-verify behavior can never
   * drift apart.
   */
  const completeChallenge = async () => {
    loggingService.debug('[MfaChallenge] Setting authenticated=true');
    await authStore.setAuthenticated(true);
    loggingService.debug('[MfaChallenge] After setAuthenticated - auth complete');
    // Redirect to saved path or dashboard
    const destination = redirectPath.value || '/';
    loggingService.debug('[MfaChallenge] Redirecting to', { destination });
    router.push(destination);
  };

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
      await completeChallenge();
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

  // Verify with a passkey (webauthn second factor)
  const handleVerifyWebAuthn = async () => {
    clearError();
    // verifyWebAuthnMfa clears + sets the composable's own error ref, which
    // the panel surfaces directly.
    const success = await verifyWebAuthnMfa();
    loggingService.debug('[MfaChallenge] WebAuthn verification result:', { success });

    if (success) {
      await completeChallenge();
    }
  };

  // Switch between challenge modes (otp / recovery / webauthn)
  const switchMode = (target: ChallengeMode) => {
    mode.value = target;
    clearError();
    clearWebAuthnError();
    otpCode.value = '';
    recoveryCode.value = '';

    if (target === 'otp') {
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
      await completeChallenge();
    } else {
      // Clear input on error
      recoveryCode.value = '';
    }
  };

  // Handle cancel - logout and return to signin
  const handleCancel = async () => {
    clearError();
    clearWebAuthnError();
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
        <!-- Unsupported browser (terminal): webauthn is the account's only
             completable factor and this browser cannot perform the ceremony.
             Mirrors the PasskeySettings unsupported notice; Cancel (footer)
             remains the exit. -->
        <div
          v-if="webauthnUnsupported"
          data-testid="mfa-webauthn-unsupported"
          class="rounded-lg bg-yellow-50 p-6 dark:bg-yellow-900/20"
          role="alert">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle-solid"
              class="size-8 text-yellow-600 dark:text-yellow-400"
              aria-hidden="true" />
            <div>
              <h3 class="font-semibold text-yellow-800 dark:text-yellow-200">
                {{ t('web.auth.webauthn.notSupported') }}
              </h3>
              <p class="mt-1 text-sm text-yellow-700 dark:text-yellow-300">
                {{ t('web.auth.webauthn.requiresModernBrowser') }}
              </p>
            </div>
          </div>
        </div>

        <!-- OTP Mode -->
        <div v-else-if="mode === 'otp'" data-testid="mfa-otp-panel">
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
            aria-atomic="true"
            data-testid="mfa-otp-error">
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
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            data-testid="mfa-verify-otp-submit">
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
        <div v-else-if="mode === 'recovery'" data-testid="mfa-recovery-panel">
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
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
                data-testid="mfa-recovery-code-input" />
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
              class="w-full rounded-md bg-brand-600 px-4 py-2 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              data-testid="mfa-recovery-submit">
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

        <!-- WebAuthn (passkey) Mode -->
        <div v-else data-testid="mfa-webauthn-panel">
          <!-- Mode announcement (screen reader only) -->
          <div aria-live="polite" class="sr-only">
            {{ t('web.auth.mfa.passkey_mode_active') }}
          </div>

          <p id="webauthn-instructions" class="mb-4 text-center text-gray-600 dark:text-gray-400">
            {{ t('web.auth.mfa.passkey_prompt') }}
          </p>

          <!-- Error message (composable's own error ref) -->
          <div
            v-if="webauthnError"
            id="webauthn-error"
            class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert"
            aria-live="assertive"
            aria-atomic="true"
            data-testid="mfa-webauthn-error">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ webauthnError }}
            </p>
          </div>

          <!-- Verify button -->
          <button
            @click="handleVerifyWebAuthn"
            :disabled="webauthnLoading"
            :aria-describedby="webauthnError ? 'webauthn-error' : 'webauthn-instructions'"
            type="button"
            class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            data-testid="mfa-verify-webauthn-submit">
            <span v-if="webauthnLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
            <span v-else>{{ t('web.auth.mfa.verify_with_passkey') }}</span>
          </button>

          <!-- Loading state announcement (screen reader only) -->
          <div
            v-if="webauthnLoading"
            aria-live="polite"
            aria-atomic="true"
            class="sr-only">
            {{ t('web.COMMON.form_processing') }}
          </div>
        </div>
      </div>
    </template>

    <!-- Footer: Secondary actions outside the card. Alternatives only ever
         point at factors the account actually has (and, for webauthn, that the
         browser supports). -->
    <template #footer>
      <div class="border-t border-gray-200 pt-4 dark:border-gray-700">
        <nav
          :aria-label="t('web.auth.mfa.alternative_auth_options')"
          class="flex items-center justify-center gap-2 text-sm">
        <!-- OTP mode: recovery code option (when codes remain) + passkey when
             usable. Both gated: a link to a factor with nothing behind it is a
             dead end. -->
        <template v-if="webauthnUnsupported">
          <!-- Terminal unsupported state: no alternatives, Cancel only. -->
        </template>
        <template v-else-if="mode === 'otp'">
          <template v-if="hasRecoveryCodes">
            <button
              @click="switchMode('recovery')"
              type="button"
              class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300"
              data-testid="mfa-use-recovery-code">
              {{ t('web.auth.mfa.use_recovery_code_short') }}
            </button>
            <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
          </template>
          <template v-if="webauthnOffered">
            <button
              @click="switchMode('webauthn')"
              type="button"
              class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300"
              data-testid="mfa-use-webauthn">
              {{ t('web.auth.mfa.use_passkey') }}
            </button>
            <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
          </template>
        </template>
        <!-- Recovery mode: back to the initial factor (otp, or passkey for
             webauthn-only accounts). When recovery IS the initial mode
             (webauthn-only account, unsupported browser, codes remaining)
             there is no live panel to go back to — no link. -->
        <template v-else-if="mode === 'recovery'">
          <template v-if="initialMode !== 'recovery'">
            <button
              @click="switchMode(initialMode)"
              type="button"
              class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300"
              data-testid="mfa-back-to-otp">
              {{
                initialMode === 'webauthn'
                  ? t('web.auth.mfa.use_passkey')
                  : t('web.auth.mfa.back_to_code')
              }}
            </button>
            <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
          </template>
        </template>
        <!-- WebAuthn mode: back to code only when the account HAS otp;
             recovery only when codes remain -->
        <template v-else>
          <template v-if="otpEnabled">
            <button
              @click="switchMode('otp')"
              type="button"
              class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300"
              data-testid="mfa-back-to-otp">
              {{ t('web.auth.mfa.back_to_code') }}
            </button>
            <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
          </template>
          <template v-if="hasRecoveryCodes">
            <button
              @click="switchMode('recovery')"
              type="button"
              class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline dark:text-gray-400 dark:hover:text-gray-300"
              data-testid="mfa-use-recovery-code">
              {{ t('web.auth.mfa.use_recovery_code_short') }}
            </button>
            <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
          </template>
        </template>

        <button
          @click="handleCancel"
          type="button"
          :disabled="isLoading || webauthnLoading"
          class="text-gray-500 transition-colors duration-200 hover:text-gray-700 focus:outline-none focus:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400 dark:hover:text-gray-300"
          data-testid="mfa-cancel">
          {{ t('web.auth.mfa.cancel_sign_in') }}
        </button>
        </nav>
      </div>
    </template>
  </AuthView>
</template>
