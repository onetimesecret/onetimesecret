<!-- src/apps/secret/components/HomepageLinksPlaceholder.vue -->

<script setup lang="ts">

  defineProps({
    title: { type: String, default: 'No secrets yet' },
    description: { type: String, default: 'Create a secret above to get started.' },
  });
</script>

<template>
  <div
    class="group relative overflow-hidden rounded-lg bg-white p-8 text-center shadow-lg transition-all duration-300 dark:bg-gray-800"
    role="region"
    :aria-label="title"
    tabindex="0">
    <div
      class="absolute inset-0 opacity-0 transition-opacity duration-300 group-hover:opacity-20"
      aria-hidden="true"></div>

    <h3
      class="relative mb-2 text-lg font-medium text-gray-500 dark:text-gray-100"
      :id="title.toLowerCase().replace(/\s+/g, '-')">
      {{ title }}
    </h3>

    <p
      class="relative text-gray-400 dark:text-gray-400"
      :aria-describedby="title.toLowerCase().replace(/\s+/g, '-')">
      {{ description }}
    </p>

    <!-- Focus outline for keyboard navigation -->
    <div
      class="absolute inset-0 rounded-lg opacity-0 ring-2 ring-blue-500 ring-offset-2 focus-within:opacity-100"
      aria-hidden="true"></div>
  </div>
</template>

<style>

</style>
