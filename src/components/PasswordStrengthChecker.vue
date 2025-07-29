<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

const password = ref('');
const confirmPassword = ref('');
const strength = ref(0);
const passwordMismatch = ref(false);
const showMismatch = ref(false);
const { t } = useI18n();

const strengthText = computed(() => {
  const strengthLabels: Record<number, string> = {
    0: t('not-great'),
    1: t('meh'),
    2: t('fair'),
    3: t('pretty-good'),
    4: t('great')
  };
  return strengthLabels[strength.value];
});

const strengthClass = computed(() => strength.value > 2 ? 'text-green-500-dark-text-green-400' : 'text-red-500-dark-text-red-400');

const checkPasswordStrength = (pass: string) => {
  let score = 0;
  if (pass.match(/[a-z]/) && pass.match(/[A-Z]/)) score++;
  if (pass.match(/\d/)) score++;
  if (pass.match(/[^a-zA-Z\d]/)) score++;
  if (pass.length >= 6) score++;
  if (pass.length <= 6) score = 0;
  strength.value = score;
};

const checkPasswordMatch = () => {
  passwordMismatch.value = password.value !== confirmPassword.value;
};

onMounted(() => {
  const passField = document.getElementById('passField') as HTMLInputElement | null;
  const pass2Field = document.getElementById('pass2Field') as HTMLInputElement | null;

  if (passField && pass2Field) {
    passField.addEventListener('input', (e) => {
      password.value = (e.target as HTMLInputElement).value;
      checkPasswordStrength(password.value);
      if (showMismatch.value) {
        checkPasswordMatch();
      }
    });

    pass2Field.addEventListener('input', (e) => {
      confirmPassword.value = (e.target as HTMLInputElement).value;
      showMismatch.value = true;
      checkPasswordMatch();
    });
  }
});
</script>

<template>
  <div>
    <div
      v-if="password"
      :class="strengthClass"
      class="mb-4">
      {{ $t('password-strength') }} <span class="font-bold">{{ strengthText }}</span>
    </div>
    <div
      v-if="showMismatch && passwordMismatch"
      class="mb-4 text-red-500 dark:text-red-400">
      {{ $t('passwords-do-not-match') }}
    </div>
  </div>
</template>
