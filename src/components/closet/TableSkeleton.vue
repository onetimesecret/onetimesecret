<!-- src/components/closet/TableSkeleton.vue -->

<template>
  <div class="animate-pulse">
    <div class="h-12 bg-gray-200 rounded-t dark:bg-gray-700 mb-4"></div>
    <div
      v-for="n in 3"
      :key="n"
      class="h-16 bg-gray-100 dark:bg-gray-800 mb-2"></div>
  </div>
</template>
