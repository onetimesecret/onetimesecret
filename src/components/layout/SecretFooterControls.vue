<!-- src/components/layout/SecretFooterControls.vue -->

<script setup lang="ts">
  import ThemeToggle from '@/components/ThemeToggle.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';

  defineProps<{
    showLanguage?: boolean;
  }>();
</script>

<template>
  <div class="flex justify-center pt-16">
    <ThemeToggle />
    <LanguageToggle
      v-if="showLanguage"
      :compact="true" />
  </div>
</template>
