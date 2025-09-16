
<script setup lang="ts">
import { defineProps } from 'vue';

const props = defineProps({
  tagline1: {
    type: String,
    required: true
  },
  tagline2: {
    type: String,
    required: true
  }
});
</script>

<template>
  <div class="flex flex-col items-center text-center">
    <h1 class="mb-2 text-2xl text-gray-600 dark:text-gray-100 sm:mx-12 sm:block md:mx-2">
      {{ props.tagline2 }}
    </h1>
    <p class="mx-12 mb-6 text-base text-gray-600 dark:text-gray-300 sm:mx-2">
      {{ props.tagline1 }}
    </p>
  </div>
</template>
