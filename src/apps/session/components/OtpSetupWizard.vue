<!-- src/apps/session/components/OtpSetupWizard.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OtpCodeInput from '@/apps/session/components/OtpCodeInput.vue';
import { useMfa } from '@/shared/composables/useMfa';
import { useClipboard } from '@/shared/composables/useClipboard';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { ref, computed, onMounted } from 'vue';

const emit = defineEmits<{
  complete: [recoveryCodes: string[]];
  cancel: [];
}>();

const { t } = useI18n();
const { setupData, recoveryCodes, isLoading, error, setupMfa, enableMfa } = useMfa();
const notificationsStore = useNotificationsStore();
const { copyToClipboard } = useClipboard();

const bootstrapStore = useBootstrapStore();
const { email, brand_product_name } = storeToRefs(bootstrapStore);

// Simplified wizard: setup or codes
const currentStep = ref<'setup' | 'codes'>('setup');
// Track whether recovery codes have been saved (downloaded or copied)
const codesSaved = ref(false);
const otpCode = ref('');
const password = ref('');
const otpInputRef = ref<InstanceType<typeof OtpCodeInput> | null>(null);

// Auto-load QR code on mount (without password initially)
onMounted(async () => {
  // Get site name and user email from bootstrap store
  const siteName = brand_product_name.value || 'OTS';
  const userEmail = email.value || '';

  await setupMfa(siteName, userEmail);
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
  codesSaved.value = true;
  notificationsStore.show(t('web.auth.recovery_codes.downloaded'), 'success', 'top');
};

// Copy codes to clipboard
const copyCodes = async () => {
  const content = recoveryCodes.value.join('\n');
  const success = await copyToClipboard(content);
  if (success) {
    codesSaved.value = true;
    notificationsStore.show(t('web.auth.recovery_codes.copied'), 'success', 'top');
  } else {
    notificationsStore.show(t('web.auth.recovery_codes.copy_failed'), 'error', 'top');
  }
};

const canVerify = computed(() => password.value && otpCode.value.length === 6 && !isLoading.value);
</script>

<template>
  <div class="space-y-6">
    <!-- Single-View Setup: QR Code, Password, and OTP Verification -->
    <div v-if="currentStep === 'setup'">
      <h2 class="mb-4 text-2xl font-bold dark:text-white">
        {{ t('web.auth.mfa.setup_title') }}
      </h2>
      <p class="mb-6 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.mfa.setup_description') }}
      </p>

      <!-- Loading state -->
      <div v-if="isLoading && !setupData" class="flex items-center justify-center py-12">
        <i class="fas fa-spinner fa-spin mr-2 text-2xl text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">{{ t('web.auth.mfa.generating_qr') }}</span>
      </div>

      <!-- Setup Form -->
      <div v-else-if="setupData" class="space-y-6">
        <!-- Step 1: QR Code & Manual Entry -->
        <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <h3 class="mb-4 text-lg font-semibold dark:text-white">
            {{ t('web.auth.mfa.step_scan') || '1. Scan QR Code' }}
          </h3>
          <div class="flex flex-col items-center">
            <p class="mb-4 text-sm text-gray-700 dark:text-gray-300">
              {{ t('web.auth.mfa.scan_qr') }}
            </p>
            <img
              :src="setupData.qr_code"
              alt="QR Code for authenticator app"
              class="mb-4 size-64 rounded-lg border-4 border-white shadow-lg dark:border-gray-800" />
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.auth.mfa.supported_apps') }}
            </p>
          </div>

          <!-- Manual Entry -->
          <div class="mt-4 rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-900">
            <p class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.auth.mfa.manual_entry') }}
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
              {{ t('web.auth.mfa.step_verify') || '2. Verify Setup' }}
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
              readonly />

            <div class="mb-4">
              <label for="mfa-password" class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.auth.mfa.password_confirmation') }}
              </label>
              <input
                id="mfa-password"
                v-model="password"
                type="password"
                autocomplete="current-password"
                :disabled="isLoading"
                :placeholder="t('web.auth.mfa.password_placeholder')"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.auth.mfa.password_reason') }}
              </p>
            </div>

            <!-- OTP Code Input -->
            <div>
              <label class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.auth.mfa.enter_code') || 'Enter verification code' }}
              </label>
              <OtpCodeInput
                ref="otpInputRef"
                :disabled="isLoading"
                @complete="handleOtpComplete" />
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.auth.mfa.enter_code_description') }}
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
              <span v-else>{{ t('web.auth.mfa.enable_and_continue') || 'Enable MFA' }}</span>
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
        {{ t('web.auth.recovery_codes.title') }}
      </h2>
      <p class="mb-2 text-gray-600 dark:text-gray-400">
        {{ t('web.auth.recovery_codes.description') }}
      </p>
      <p class="mb-6 text-sm font-semibold text-yellow-700 dark:text-yellow-400">
        {{ t('web.auth.recovery_codes.warning') }}
      </p>

      <!-- Save requirement warning -->
      <div
        v-if="!codesSaved"
        role="alert"
        class="mb-4 rounded-lg border border-amber-300 bg-amber-50 p-4 dark:border-amber-600 dark:bg-amber-900/20">
        <div class="flex items-start">
          <i class="fas fa-exclamation-triangle mr-3 mt-0.5 text-amber-600 dark:text-amber-400"></i>
          <p class="text-sm text-amber-800 dark:text-amber-200">
            {{ t('web.auth.recovery_codes.save_required') }}
          </p>
        </div>
      </div>

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
          {{ t('web.auth.recovery_codes.download') }}
        </button>
        <button
          @click="copyCodes"
          type="button"
          class="flex-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
          <i class="fas fa-copy mr-2"></i>
          {{ t('web.auth.recovery_codes.copy') }}
        </button>
      </div>

      <!-- Complete button -->
      <button
        @click="handleComplete"
        type="button"
        :disabled="!codesSaved"
        :class="[
          'mt-6 w-full rounded-md px-4 py-3 text-lg font-medium focus:outline-none focus:ring-2 focus:ring-offset-2',
          codesSaved
            ? 'bg-green-600 text-white hover:bg-green-700 focus:ring-green-500'
            : 'cursor-not-allowed bg-gray-400 text-gray-200'
        ]">
        <i class="fas fa-check mr-2"></i>
        {{ t('web.auth.mfa.complete_setup') }}
      </button>
    </div>
  </div>
</template>
