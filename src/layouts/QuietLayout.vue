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
import BaseLayout from './BaseLayout.vue';
import type { Props as BaseLayoutProps } from '@/layouts/BaseLayout.vue';

// Define the props for this layout, extending the BaseLayout props
interface ImplementingLayoutProps extends BaseLayoutProps {
  // Add any additional props specific to this layout
  //additionalProp?: string;
}

const props = withDefaults(defineProps<ImplementingLayoutProps>(), {

  // You can also add defaults for optional BaseLayout props
  displayMasthead: false,
  displayLinks: false,
  displayFeedback: false,
  displayVersion: false,

});
</script>
