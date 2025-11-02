<!-- src/components/layout/ExpandedHeader.vue -->

<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import MastHead from '@/components/layout/MastHead.vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });
</script>

<template>
  <header class="bg-white dark:bg-gray-900">
    <div class="container mx-auto min-w-[320px] max-w-4xl p-4">
      <MastHead v-if="displayMasthead" v-bind="props" />
    </div>
  </header>
</template>
