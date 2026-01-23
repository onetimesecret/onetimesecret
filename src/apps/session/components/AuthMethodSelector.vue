<!-- src/apps/session/components/AuthMethodSelector.vue -->

<script setup lang="ts">
import { isMagicLinksEnabled, isWebAuthnEnabled } from '@/utils/features';
import { ref, computed } from 'vue';

import PasswordlessFirstSignIn from './PasswordlessFirstSignIn.vue';
import SignInForm from './SignInForm.vue';

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
  <div>
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
  </div>
</template>
