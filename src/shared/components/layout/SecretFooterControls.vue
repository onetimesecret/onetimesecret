<!-- src/components/layout/SecretFooterControls.vue -->

<script setup lang="ts">
  import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
  import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';
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
      :compact="true"
      max-height="max-h-dvh" />
  </div>
</template>
