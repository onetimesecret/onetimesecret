<script setup lang="ts">
import OtpCodeInput from '@/components/auth/OtpCodeInput.vue';
import { useMfa } from '@/composables/useMfa';
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

const emit = defineEmits<{
  complete: [recoveryCodes: string[]];
  cancel: [];
}>();

const { t } = useI18n();
const { setupData, recoveryCodes, isLoading, error, setupMfa, enableMfa } = useMfa();

// Simplified wizard: setup or codes
const currentStep = ref<'setup' | 'codes'>('setup');
const otpCode = ref('');
const password = ref('');
const otpInputRef = ref<InstanceType<typeof OtpCodeInput> | null>(null);

// Auto-load QR code on mount (without password initially)
onMounted(async () => {
  await setupMfa();
});

// Handle OTP code input
const handleOtpComplete = (code: string) => {
  otpCode.value = code;
};

// Verify OTP and move to recovery codes step
const handleVerify = async () => {
  if (!password.value || otpCode.value.length !== 6) {
    return;
  }

  const success = await enableMfa(otpCode.value, password.value);
  if (success) {
    // Recovery codes are automatically included in enableMfa response
    // No need to fetch separately
    currentStep.value = 'codes';
  } else {
    // Clear OTP input on error
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

const canVerify = computed(() => password.value && otpCode.value.length === 6 && !isLoading.value);
</script>

<template>
  <div class="space-y-6">
    <!-- Single-View Setup: QR Code, Password, and OTP Verification -->
    <div v-if="currentStep === 'setup'">
      <h2 class="mb-4 text-2xl font-bold dark:text-white">
        {{ t('web.auth.mfa.setup-title') }}
      </h2>
      <p class="mb-6 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.mfa.setup-description') }}
      </p>

      <!-- Loading state -->
      <div v-if="isLoading && !setupData" class="flex items-center justify-center py-12">
        <i class="fas fa-spinner fa-spin mr-2 text-2xl text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">{{ t('web.auth.mfa.generating-qr') }}</span>
      </div>

      <!-- Setup Form -->
      <div v-else-if="setupData" class="space-y-6">
        <!-- Step 1: QR Code & Manual Entry -->
        <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <h3 class="mb-4 text-lg font-semibold dark:text-white">
            {{ t('web.auth.mfa.step-scan') || '1. Scan QR Code' }}
          </h3>
          <div class="flex flex-col items-center">
            <p class="mb-4 text-sm text-gray-700 dark:text-gray-300">
              {{ t('web.auth.mfa.scan-qr') }}
            </p>
            <img
              :src="setupData.qr_code"
              alt="QR Code for authenticator app"
              class="mb-4 rounded-lg border-4 border-white shadow-lg size-64 dark:border-gray-800"
            />
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.auth.mfa.supported-apps') }}
            </p>
          </div>

          <!-- Manual Entry -->
          <div class="mt-4 rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-900">
            <p class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.auth.mfa.manual-entry') }}
            </p>
            <code
              class="block break-all rounded bg-white p-2 font-mono text-sm dark:bg-gray-800 dark:text-gray-300">
              {{ setupData.otp_setup }}
            </code>
          </div>
        </div>

        <!-- Step 2: Verification Form -->
        <form @submit.prevent="handleVerify" class="space-y-6">
          <!-- Password Input -->
          <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
            <h3 class="mb-4 text-lg font-semibold dark:text-white">
              {{ t('web.auth.mfa.step-verify') || '2. Verify Setup' }}
            </h3>

            <!-- Hidden username field for accessibility/password managers -->
            <input
              type="email"
              name="username"
              autocomplete="username"
              value=""
              class="sr-only"
              tabindex="-1"
              aria-hidden="true"
              readonly
            />

            <div class="mb-4">
              <label for="mfa-password" class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.auth.mfa.password-confirmation') }}
              </label>
              <input
                id="mfa-password"
                v-model="password"
                type="password"
                autocomplete="current-password"
                :disabled="isLoading"
                :placeholder="t('web.auth.mfa.password-placeholder')"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              />
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.auth.mfa.password-reason') }}
              </p>
            </div>

            <!-- OTP Code Input -->
            <div>
              <label class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.auth.mfa.enter-code') || 'Enter verification code' }}
              </label>
              <OtpCodeInput
                ref="otpInputRef"
                :disabled="isLoading"
                @complete="handleOtpComplete"
              />
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.auth.mfa.enter-code-description') }}
              </p>
            </div>
          </div>

          <!-- Error message -->
          <div
            v-if="error"
            class="rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
            role="alert">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ error }}
            </p>
          </div>

          <!-- Action buttons -->
          <div class="flex gap-3">
            <button
              @click="handleCancel"
              type="button"
              :disabled="isLoading"
              class="flex-1 rounded-md border border-gray-300 px-4 py-3 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
              {{ t('web.COMMON.word_cancel') }}
            </button>
            <button
              type="submit"
              :disabled="!canVerify"
              class="flex-1 rounded-md bg-brand-600 px-4 py-3 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
              <span v-else>{{ t('web.auth.mfa.enable-and-continue') || 'Enable MFA' }}</span>
            </button>
          </div>
        </form>
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

    <!-- Recovery Codes Step -->
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
