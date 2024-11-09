<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props"/>
    </template>

    <template #main>
      <main class="container mx-auto px-4 py-8 min-w-[320px] max-w-2xl" name="DefaultLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <DefaultFooter v-bind="props"/>
    </template>
  </BaseLayout>
</template>

<script setup lang="ts">
import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import type { Props as BaseProps } from '@/layouts/BaseLayout.vue';

import BaseLayout from './BaseLayout.vue';

// Define the props for this layout, extending the BaseLayout props
export interface Props extends BaseProps {
  displayFeedback?: boolean
  displayLinks?: boolean
  displayMasthead?: boolean
  displayNavigation?: boolean
  displayVersion?: boolean
  displayToggles?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  displayFeedback: true,
  displayLinks: true,
  displayMasthead: true,
  displayNavigation: true,
  displayVersion: true,
  displayToggles: true,
})
</script>
