<script setup lang="ts">
import OtpCodeInput from '@/components/auth/OtpCodeInput.vue';
import { useMfa } from '@/composables/useMfa';
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

const emit = defineEmits<{
  complete: [recoveryCodes: string[]];
  cancel: [];
}>();

const { t } = useI18n();
const { setupData, recoveryCodes, isLoading, error, setupMfa, enableMfa, fetchRecoveryCodes } = useMfa();

// Wizard steps: password, setup, verify, codes
const currentStep = ref<'password' | 'setup' | 'verify' | 'codes'>('password');
const otpCode = ref('');
const password = ref('');
const otpInputRef = ref<InstanceType<typeof OtpCodeInput> | null>(null);

// Password collection first, then setup
const handlePasswordSubmit = async () => {
  if (!password.value) return;

  // Load QR code with password, then move to setup step on success
  const result = await setupMfa(password.value);
  if (result) {
    currentStep.value = 'setup';
  }
};

// Handle OTP code input
const handleOtpComplete = (code: string) => {
  otpCode.value = code;
};

// Verify OTP and move to recovery codes step
const handleVerify = async () => {
  if (otpCode.value.length !== 6) {
    return;
  }

  const success = await enableMfa(otpCode.value, password.value);
  if (success) {
    // Fetch recovery codes
    await fetchRecoveryCodes();
    currentStep.value = 'codes';
  } else {
    // Clear input on error
    otpInputRef.value?.clear();
    otpCode.value = '';
    // Don't clear password to allow retry
  }
};

// Complete wizard
const handleComplete = () => {
  emit('complete', recoveryCodes.value);
};

// Cancel wizard
const handleCancel = () => {
  emit('cancel');
};

// Download recovery codes as text file
const downloadCodes = () => {
  const content = recoveryCodes.value.join('\n');
  const blob = new Blob([content], { type: 'text/plain' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'onetime-recovery-codes.txt';
  a.click();
  URL.revokeObjectURL(url);
};

// Copy codes to clipboard
const copyCodes = async () => {
  const content = recoveryCodes.value.join('\n');
  try {
    await navigator.clipboard.writeText(content);
    alert(t('web.auth.recovery-codes.copied'));
  } catch (err) {
    console.error('Failed to copy:', err);
  }
};

const canVerify = computed(() => otpCode.value.length === 6 && !isLoading.value);
</script>

<template>
  <div class="space-y-6">
    <!-- Step 0: Password Confirmation -->
    <div v-if="currentStep === 'password'">
      <h2 class="mb-4 text-2xl font-bold dark:text-white">
        {{ t('web.auth.mfa.setup-title') }}
      </h2>
      <p class="mb-6 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.mfa.password-reason') }}
      </p>

      <!-- Password Input -->
      <form @submit.prevent="handlePasswordSubmit">
        <div class="mb-6">
          <label for="mfa-password" class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.auth.mfa.password-confirmation') }}
          </label>
          <input
            id="mfa-password"
            v-model="password"
            type="password"
            :disabled="isLoading"
            :placeholder="t('web.auth.mfa.password-placeholder')"
            autofocus
            class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          />
        </div>

        <!-- Error message -->
        <div
          v-if="error"
          class="mb-4 rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
          role="alert">
          <p class="text-sm text-red-800 dark:text-red-200">
            {{ error }}
          </p>
        </div>

        <!-- Continue button -->
        <button
          type="submit"
          :disabled="!password || isLoading"
          class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
          <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
          <span v-else>{{ t('web.COMMON.word_continue') }}</span>
        </button>

        <button
          @click="handleCancel"
          type="button"
          class="mt-3 w-full text-sm text-gray-600 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200">
          {{ t('web.COMMON.word_cancel') }}
        </button>
      </form>
    </div>

    <!-- Step 1: QR Code & Manual Entry -->
    <div v-else-if="currentStep === 'setup'">
      <h2 class="mb-4 text-2xl font-bold dark:text-white">
        {{ t('web.auth.mfa.setup-title') }}
      </h2>
      <p class="mb-6 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.mfa.setup-description') }}
      </p>

      <!-- Loading state -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <i class="fas fa-spinner fa-spin mr-2 text-2xl text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">{{ t('web.auth.mfa.generating-qr') }}</span>
      </div>

      <!-- Setup data -->
      <div v-else-if="setupData" class="space-y-6">
        <!-- QR Code -->
        <div class="flex flex-col items-center rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <p class="mb-4 text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.auth.mfa.scan-qr') }}
          </p>
          <img
            :src="setupData.qr_code"
            alt="QR Code for authenticator app"
            class="mb-4 rounded-lg border-4 border-white shadow-lg size-96 dark:border-gray-800"
          />
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.auth.mfa.supported-apps') }}
          </p>
        </div>

        <!-- Manual Entry -->
        <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-800">
          <p class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.auth.mfa.manual-entry') }}
          </p>
          <code
            v-if="setupData.otp_raw_secret"
            class="block break-all rounded bg-gray-100 p-2 font-mono text-sm dark:bg-gray-900 dark:text-gray-300">
            {{ setupData.otp_raw_secret }}
          </code>
        </div>

        <!-- Next button -->
        <button
          @click="currentStep = 'verify'"
          type="button"
          class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
          {{ t('web.auth.mfa.continue-verification') }}
        </button>

        <button
          @click="handleCancel"
          type="button"
          class="w-full text-sm text-gray-600 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200">
          {{ t('web.COMMON.word_cancel') }}
        </button>
      </div>

      <!-- Error state -->
      <div
        v-else-if="error"
        class="rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
        role="alert">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>
    </div>

    <!-- Step 2: Verify OTP -->
    <div v-else-if="currentStep === 'verify'">
      <h2 class="mb-4 text-2xl font-bold dark:text-white">
        {{ t('web.auth.mfa.verify-code') }}
      </h2>
      <p class="mb-6 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.mfa.enter-code-description') }}
      </p>

      <!-- OTP Input -->
      <div class="mb-6">
        <OtpCodeInput
          ref="otpInputRef"
          :disabled="isLoading"
          @complete="handleOtpComplete"
        />
      </div>

      <!-- Error message -->
      <div
        v-if="error"
        class="mb-4 rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
        role="alert">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>

      <!-- Verify button -->
      <button
        @click="handleVerify"
        :disabled="!canVerify"
        type="button"
        class="w-full rounded-md bg-brand-600 px-4 py-3 text-lg font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
        <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
        <span v-else>{{ t('web.auth.mfa.verify') }}</span>
      </button>

      <button
        @click="currentStep = 'setup'"
        type="button"
        class="mt-3 w-full text-sm text-gray-600 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200">
        {{ t('web.COMMON.back') }}
      </button>
    </div>

    <!-- Step 3: Recovery Codes -->
    <div v-else-if="currentStep === 'codes'">
      <h2 class="mb-4 text-2xl font-bold dark:text-white">
        {{ t('web.auth.recovery-codes.title') }}
      </h2>
      <p class="mb-2 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.recovery-codes.description') }}
      </p>
      <p class="mb-6 text-sm font-semibold text-yellow-700 dark:text-yellow-400">
        {{ t('web.auth.recovery-codes.warning') }}
      </p>

      <!-- Recovery codes list -->
      <div class="mb-6 rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
        <div class="grid grid-cols-2 gap-3">
          <div
            v-for="(code, index) in recoveryCodes"
            :key="index"
            class="rounded bg-white p-2 font-mono text-sm dark:bg-gray-700 dark:text-gray-300">
            {{ code }}
          </div>
        </div>
      </div>

      <!-- Action buttons -->
      <div class="flex gap-3">
        <button
          @click="downloadCodes"
          type="button"
          class="flex-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
          <i class="fas fa-download mr-2"></i>
          {{ t('web.auth.recovery-codes.download') }}
        </button>
        <button
          @click="copyCodes"
          type="button"
          class="flex-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
          <i class="fas fa-copy mr-2"></i>
          {{ t('web.auth.recovery-codes.copy') }}
        </button>
      </div>

      <!-- Complete button -->
      <button
        @click="handleComplete"
        type="button"
        class="mt-6 w-full rounded-md bg-green-600 px-4 py-3 text-lg font-medium text-white hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2">
        <i class="fas fa-check mr-2"></i>
        {{ t('web.auth.mfa.complete-setup') }}
      </button>
    </div>
  </div>
</template>
