<!-- src/components/secrets/HomepageLinksPlaceholder.vue -->

<script setup lang="ts">

  defineProps({
    title: { type: String, default: 'No secrets yet' },
    description: { type: String, default: 'Create a secret above to get started.' },
  });
</script>

<template>
  <div
    class="group relative overflow-hidden bg-white dark:bg-gray-800 rounded-lg shadow-lg p-8 text-center transition-all duration-300"
    role="region"
    :aria-label="title"
    tabindex="0">

    <div
      class="absolute inset-0 opacity-0 group-hover:opacity-20 transition-opacity duration-300"
      aria-hidden="true"></div>

    <h3
      class="relative text-lg font-medium text-gray-500 dark:text-gray-100 mb-2"
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
      class="absolute inset-0 rounded-lg ring-2 ring-offset-2 ring-blue-500 opacity-0 focus-within:opacity-100"
      aria-hidden="true"></div>
  </div>
</template>

<style>

</style>
