<!-- src/shared/components/forms/PasswordStrengthChecker.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { computed } from 'vue';

const props = defineProps<{
  /** The primary password value to check strength for */
  password: string;
  /** The confirmation password to check for match */
  confirmPassword?: string;
}>();

const { t } = useI18n();

const strength = computed(() => {
  const pass = props.password;
  if (!pass || pass.length <= 6) return 0;
  let score = 0;
  if (pass.match(/[a-z]/) && pass.match(/[A-Z]/)) score++;
  if (pass.match(/\d/)) score++;
  if (pass.match(/[^a-zA-Z\d]/)) score++;
  if (pass.length >= 6) score++;
  return score;
});

const strengthText = computed(() => {
  const strengthLabels: Record<number, string> = {
    0: t('web.COMMON.not_great'),
    1: t('web.COMMON.meh'),
    2: t('web.COMMON.fair'),
    3: t('web.COMMON.pretty_good'),
    4: t('web.COMMON.great')
  };
  return strengthLabels[strength.value];
});

const strengthClass = computed(() =>
  strength.value > 2 ? 'text-green-500 dark:text-green-400' : 'text-red-500 dark:text-red-400'
);

const showMismatch = computed(() =>
  props.confirmPassword !== undefined && props.confirmPassword.length > 0
);

const passwordMismatch = computed(() =>
  showMismatch.value && props.password !== props.confirmPassword
);
</script>

<template>
  <div>
    <div
      v-if="password"
      :class="strengthClass"
      class="mb-4"
      aria-live="polite">
      {{ t('web.COMMON.password_strength') }} <span class="font-bold">{{ strengthText }}</span>
    </div>
    <div
      v-if="showMismatch && passwordMismatch"
      class="mb-4 text-red-500 dark:text-red-400"
      aria-live="polite">
      {{ t('web.COMMON.passwords_do_not_match') }}
    </div>
  </div>
</template>
