<!-- EmailObfuscator.vue -->

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

interface Props {
  email: string;
  subject?: string;
}

const props = withDefaults(defineProps<Props>(), {
  subject: '',
});
const { t } = useI18n();

const obfuscateEmail = (email: string): string => email.replace('@', ' &#65;&#84; ').replace('.', ' D0T ');

const deobfuscateEmail = (email: string): string => email
    .replace(/ &#65;&#84; /g, "@")
    .replace(/ AT /g, "@")
    .replace(/ D0T /g, ".");

const displayedEmail = ref(obfuscateEmail(props.email));

const handleClick = async () => {
  const deobfuscatedEmail = deobfuscateEmail(props.email);

  // Copy email to clipboard
  try {
    await navigator.clipboard.writeText(deobfuscatedEmail);
    alert(t('email-address-copied-to-clipboard'));
  } catch (err) {
    console.error('Failed to copy email: ', err);
  }

};

onMounted(() => {
  displayedEmail.value = deobfuscateEmail(props.email);
});
</script>

<template>
  <a
    @click="handleClick"
    class="email cursor-pointer text-brand-500 hover:underline dark:text-brand-400">
    {{ displayedEmail }}
  </a>
</template>
