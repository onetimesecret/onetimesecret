<!-- src/components/ButtonGroup.vue -->

<script setup lang="ts">
// Define your component's props
defineProps({
  firstVal: String, // Assuming val1 is already being used as shown in your template
  midVal1: String,
  lastVal: String,
});
</script>

<template>
  <span class="isolate inline-flex rounded-md shadow-sm">
    <button
      type="button"
      class="relative inline-flex items-center rounded-l-md bg-white px-3 py-2 text-sm font-semibold text-gray-500 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 hover:text-gray-700 focus:z-10">{{ firstVal }}</button>
    <!--<button type="button" class="relative -ml-px inline-flex items-center bg-white px-3 py-2 text-sm font-semibold text-gray-500 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:z-10">{{ midVal1 }}</button>-->
    <button
      type="button"
      class="relative -ml-px inline-flex items-center rounded-r-md bg-white px-3 py-2 text-sm font-semibold text-gray-500 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:z-10">{{ lastVal }}</button>
  </span>
</template>
