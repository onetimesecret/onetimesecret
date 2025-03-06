<!-- src/components/layout/SecretFooterControls.vue -->

<script setup lang="ts">
  import ThemeToggle from '@/components/ThemeToggle.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';
import { WindowService } from '@/services/window.service';

  defineProps<{
    showLanguage?: boolean;
  }>();

  const windowProps = WindowService.getMultiple([
    'i18n_enabled',
  ]);
</script>

<template>
  <div class="flex justify-center pt-16">
    <ThemeToggle />
    <LanguageToggle
      v-if="windowProps.i18n_enabled && showLanguage"
      :compact="true" />
  </div>
</template>
