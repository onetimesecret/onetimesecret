<script setup lang="ts">
import BaseLayout from './BaseLayout.vue';

// Pass through all props from BaseLayout
//const props = defineProps<InstanceType<typeof BaseLayout>['$props']>();
</script>

<template>
  <BaseLayout v-bind="props">
    <template #main>
      <main class="container mx-auto p-4">
        <slot></slot>
      </main>
    </template>
  </BaseLayout>
</template>
