<template>
  <BaseLayout v-bind="props">
    <template #main>
      <main class="container mx-auto p-4 max-w-2xl" name="QuietLayout">
        <slot></slot>
      </main>
    </template>
  </BaseLayout>
</template>

<script setup lang="ts">
import type { Props as BaseProps } from '@/layouts/BaseLayout.vue';
import BaseLayout from './BaseLayout.vue';

// Define the props for this layout, extending the BaseLayout props
export interface Props extends BaseProps {
}

const props = withDefaults(defineProps<Props>(), {
});
</script>
