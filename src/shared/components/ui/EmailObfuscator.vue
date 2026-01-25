<!-- src/shared/components/ui/EmailObfuscator.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { ref, onMounted } from 'vue';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';

interface Props {
  email: string;
  subject?: string;
}

const props = withDefaults(defineProps<Props>(), {
  subject: '',
});
const { t } = useI18n();
const notifications = useNotificationsStore();

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
    notifications.show(t('web.COMMON.email_address_copied_to_clipboard'), 'success');
  } catch (err) {
    console.error('Failed to copy email: ', err);
    notifications.show(t('web.COMMON.unexpected_error'), 'error');
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
