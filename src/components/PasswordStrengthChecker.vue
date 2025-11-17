<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

// Use defineModel for two-way binding with parent component
const password = defineModel<string>('password', { default: '' });
const confirmPassword = defineModel<string>('confirmPassword', { default: '' });

// Minimum password length constant
const MIN_PASSWORD_LENGTH = 6;

// Calculate password strength
const strength = computed(() => {
  const pass = password.value;
  let score = 0;

  if (pass.length <= MIN_PASSWORD_LENGTH) return 0;

  if (pass.match(/[a-z]/) && pass.match(/[A-Z]/)) score++;
  if (pass.match(/\d/)) score++;
  if (pass.match(/[^a-zA-Z\d]/)) score++;
  if (pass.length >= MIN_PASSWORD_LENGTH) score++;

  return score;
});

const strengthText = computed(() => {
  const strengthLabels: Record<number, string> = {
    0: t('not-great'),
    1: t('meh'),
    2: t('fair'),
    3: t('pretty-good'),
    4: t('great')
  };
  return strengthLabels[strength.value] || strengthLabels[0];
});

const strengthClass = computed(() => {
  return strength.value > 2
    ? 'text-green-500 dark:text-green-400'
    : 'text-red-500 dark:text-red-400';
});

// Check if passwords match
const passwordMismatch = computed(() => {
  // Only show mismatch if confirmPassword has been entered
  return confirmPassword.value.length > 0 && password.value !== confirmPassword.value;
});

// Show mismatch message only after user starts typing in confirm field
const showMismatch = computed(() => confirmPassword.value.length > 0);
</script>

<template>
  <div>
    <div
      v-if="password"
      :class="strengthClass"
      class="mb-4"
      aria-live="polite">
      {{ t('password-strength') }} <span class="font-bold">{{ strengthText }}</span>
    </div>
    <div
      v-if="showMismatch && passwordMismatch"
      class="mb-4 text-red-500 dark:text-red-400"
      aria-live="polite">
      {{ t('passwords-do-not-match') }}
    </div>
  </div>
</template>
