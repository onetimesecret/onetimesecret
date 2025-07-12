<script setup lang="ts">
  defineProps<{
    show: boolean;
    message: string;
  }>();
</script>

<template>
  <div
    v-if="show"
    class="absolute top-3 right-3 px-3 py-1.5 bg-gray-900 dark:bg-gray-700 text-white text-sm rounded-md shadow-lg transform transition-all duration-300"
    :class="{
      'opacity-0 translate-y-1': !show,
      'opacity-100 translate-y-0': show,
    }">
    {{ message }}
  </div>
</template>
