<template>
  <!-- Router View Structure:
           - Named views allow multiple <router-view> components in a single layout.
           - The unnamed <router-view> is the default view for each route.
           - Named views ("header" and "footer") can display different components
             based on the current route configuration.
           - layoutProps are passed to each view for consistent styling and behavior. -->
  <BaseLayout v-bind="props">
    <template #header>
      <router-view
        name="header"
        v-bind="props"
      />
    </template>
    <template #main>
      <main
        class="container mx-auto max-w-2xl p-4"
        name="QuietLayout">
        <slot></slot>
      </main>
    </template>
    <template #footer>
      <router-view
        name="footer"
        v-bind="props"
      />
    </template>
  </BaseLayout>
</template>

<script setup lang="ts">
import type { Props as BaseProps } from '@/layouts/BaseLayout.vue';

import BaseLayout from './BaseLayout.vue';

const props = withDefaults(defineProps<BaseProps>(), {
});
</script>
