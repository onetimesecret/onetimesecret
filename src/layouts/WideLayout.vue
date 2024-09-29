<script setup lang="ts">
import BaseLayout from './BaseLayout.vue';
import type { Props as BaseLayoutProps } from '@/layouts/BaseLayout.vue';

// Define the props for this layout, extending the BaseLayout props
interface ImplementingLayoutProps extends BaseLayoutProps {
  // Add any additional props specific to this layout
  additionalProp?: string;
}

const props = withDefaults(defineProps<ImplementingLayoutProps>(), {

  // You can also add defaults for optional BaseLayout props
  displayMasthead: true,
  displayLinks: true,
  displayFeedback: true,

});

</script>

<template>
  <BaseLayout v-bind="props">
    <template #main>
      <main class="container mx-auto p-4" name="WideLayout">
        <slot></slot>
      </main>
    </template>
  </BaseLayout>
</template>
