
<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props"/>
    </template>

    <template #main>
      <main class="container mx-auto p-4" name="WideLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <DefaultFooter v-bind="props"/>
    </template>

  </BaseLayout>
</template>

<script setup lang="ts">
import BaseLayout from './BaseLayout.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import type { Props as BaseProps } from '@/layouts/BaseLayout.vue';

// Define the props for this layout, extending the BaseLayout props
export interface Props extends BaseProps {
  displayFeedback?: boolean
  displayLinks?: boolean
  displayMasthead?: boolean
  displayNavigation?: boolean
  displayVersion?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  displayFeedback: true,
  displayLinks: true,
  displayMasthead: true,
  displayNavigation: true,
  displayVersion: true,
});

</script>
