<!-- src/apps/secret/components/layout/SecretFooterControls.vue -->

<script setup lang="ts">
  import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
  import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';

  defineProps<{
    showLanguage?: boolean;
  }>();

  const bootstrapStore = useBootstrapStore();
  const { i18n_enabled } = storeToRefs(bootstrapStore);
</script>

<template>
  <div class="flex justify-center pt-16">
    <ThemeToggle />
    <LanguageToggle
      v-if="i18n_enabled && showLanguage"
      :compact="true"
      max-height="max-h-dvh" />
  </div>
</template>
