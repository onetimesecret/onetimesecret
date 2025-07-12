<!-- src/layouts/DefaultLayout.vue -->
<script setup lang="ts">
  import DefaultFooter from '@/components/layout/DefaultFooter.vue';
  import DefaultHeader from '@/components/layout/DefaultHeader.vue';
  import type { LayoutProps } from '@/types/ui/layouts';
  import BaseLayout from './BaseLayout.vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayMasthead: true,
    displayNavigation: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props" />
    </template>

    <template #main>
      <main
        class="container mx-auto min-w-[320px] max-w-2xl px-4 py-8"
        name="DefaultLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <DefaultFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
