<template>
  <!-- Router View Structure:
           - Named views allow multiple <router-view> components in a single layout.
           - The unnamed <router-view> is the default view for each route.
           - Named views ("header" and "footer") can display different components
             based on the current route configuration.
           - layoutProps are passed to each view for consistent styling and behavior. -->
  <BaseLayout v-bind="props">
    <template #header>
      <router-view name="header" v-bind="props"></router-view>
    </template>
    <template #main>
      <main class="container mx-auto p-4 max-w-2xl" name="QuietLayout">
        <slot></slot>
      </main>
    </template>
    <template #footer>
      <router-view name="footer" v-bind="props"></router-view>
    </template>
  </BaseLayout>
</template>

<script setup lang="ts">
import type { Props as BaseProps } from '@/layouts/BaseLayout.vue';

import BaseLayout from './BaseLayout.vue';

const props = withDefaults(defineProps<BaseProps>(), {
});
</script>
