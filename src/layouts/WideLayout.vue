<!-- src/layouts/WideLayout.vue -->
<script setup lang="ts">
import type { LayoutProps } from '@/types/ui/layouts';
import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import BaseLayout from './BaseLayout.vue';

const props = withDefaults(defineProps<LayoutProps>(), {
  displayFeedback: true,
  displayLinks: true,
  displayMasthead: true,
  displayNavigation: true,
  displayVersion: true,
  displayToggles: true,
});
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props" />
    </template>

    <template #main>
      <main
        class="container mx-auto p-4"
        name="WideLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <DefaultFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
