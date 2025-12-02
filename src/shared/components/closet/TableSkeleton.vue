<!-- src/components/closet/TableSkeleton.vue -->

<template>
  <div class="animate-pulse">
    <div class="mb-4 h-12 rounded-t bg-gray-200 dark:bg-gray-700"></div>
    <div
      v-for="n in 3"
      :key="n"
      class="mb-2 h-16 bg-gray-100 dark:bg-gray-800"></div>
  </div>
</template>
