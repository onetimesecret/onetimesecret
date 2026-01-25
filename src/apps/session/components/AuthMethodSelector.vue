<!-- src/apps/session/components/AuthMethodSelector.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { isMagicLinksEnabled, isOmniAuthEnabled, isWebAuthnEnabled } from '@/utils/features';
import { ref, computed } from 'vue';

import PasswordlessFirstSignIn from './PasswordlessFirstSignIn.vue';
import SignInForm from './SignInForm.vue';
import SsoButton from './SsoButton.vue';

const { t } = useI18n();

export interface Props {
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  locale: 'en',
});

type AuthMode = 'passwordless' | 'passkey' | 'password';

const emit = defineEmits<{
  (e: 'mode-change', mode: AuthMode): void;
}>();

// Check which methods are enabled
const magicLinksEnabled = isMagicLinksEnabled();
const webauthnEnabled = isWebAuthnEnabled();
const omniAuthEnabled = isOmniAuthEnabled();

// Show passwordless-first UI when any passwordless method is enabled
const hasPasswordlessMethods = computed(() => magicLinksEnabled || webauthnEnabled);

// Track current mode for footer context (emitted from PasswordlessFirstSignIn)
const currentMode = ref<AuthMode>('passwordless');

const handleModeChange = (mode: AuthMode) => {
  currentMode.value = mode;
  emit('mode-change', mode);
};

// Expose current mode for parent component (Login.vue) to use for footer
defineExpose({ currentMode });
</script>

<template>
  <div class="space-y-6">
    <!-- Passwordless-first mode when any passwordless method is enabled -->
    <PasswordlessFirstSignIn
      v-if="hasPasswordlessMethods"
      :locale="locale"
      :magic-links-enabled="magicLinksEnabled"
      :webauthn-enabled="webauthnEnabled"
      @mode-change="handleModeChange" />

    <!-- Password-only mode when no passwordless methods enabled -->
    <SignInForm
      v-else
      :locale="locale" />

    <!-- SSO section when OmniAuth is enabled -->
    <template v-if="omniAuthEnabled">
      <!-- Divider -->
      <div class="relative">
        <div class="absolute inset-0 flex items-center" aria-hidden="true">
          <div class="w-full border-t border-gray-300 dark:border-gray-600"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="bg-white px-2 text-gray-500 dark:bg-gray-800 dark:text-gray-400">
            {{ t('web.login.or_continue_with') }}
          </span>
        </div>
      </div>

      <!-- SSO Button -->
      <SsoButton />
    </template>
  </div>
</template>
