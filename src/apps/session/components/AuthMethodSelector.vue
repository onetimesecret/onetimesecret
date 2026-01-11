<!-- src/apps/session/components/AuthMethodSelector.vue -->

<script setup lang="ts">
import { isMagicLinksEnabled } from '@/utils/features';
import { ref } from 'vue';

import PasswordlessFirstSignIn from './PasswordlessFirstSignIn.vue';
import SignInForm from './SignInForm.vue';

export interface Props {
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  locale: 'en',
});

type AuthMode = 'passwordless' | 'password';

const emit = defineEmits<{
  (e: 'mode-change', mode: AuthMode): void;
}>();

// Check which methods are enabled
const magicLinksEnabled = isMagicLinksEnabled();

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
    <!-- Passwordless-first mode when magic links enabled -->
    <PasswordlessFirstSignIn
      v-if="magicLinksEnabled"
      :locale="locale"
      @mode-change="handleModeChange" />

    <!-- Password-only mode when magic links disabled -->
    <SignInForm
      v-else
      :locale="locale" />
  </div>
</template>
