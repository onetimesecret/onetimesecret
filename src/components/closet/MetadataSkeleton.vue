<!-- src/components/closet/MetadataSkeleton.vue -->

<template>
  <div class="space-y-8 animate-pulse">
    <!-- Secret Link Skeleton -->
    <section class="h-24 bg-gray-100 dark:bg-gray-800 rounded-lg"></section>

    <!-- Status & Timeline Skeleton -->
    <section class="bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
      <div class="flex items-center justify-between mb-4">
        <div class="h-4 w-24 bg-gray-200 dark:bg-gray-700 rounded"></div>
        <div class="h-6 w-32 bg-gray-200 dark:bg-gray-700 rounded-full"></div>
      </div>

      <div class="space-y-6">
        <div
          v-for="n in 3"
          :key="n"
          class="flex gap-4">
          <div class="w-12 h-12 bg-gray-200 dark:bg-gray-700 rounded-full"></div>
          <div class="space-y-2">
            <div class="h-4 w-32 bg-gray-200 dark:bg-gray-700 rounded"></div>
            <div class="h-3 w-48 bg-gray-200 dark:bg-gray-700 rounded"></div>
          </div>
        </div>
      </div>
    </section>

    <!-- Instructions Skeleton -->
    <section class="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 space-y-4">
      <div class="h-4 w-40 bg-gray-200 dark:bg-gray-700 rounded"></div>
      <div class="space-y-3">
        <div
          v-for="n in 3"
          :key="n"
          class="flex gap-2">
          <div class="w-5 h-5 bg-gray-200 dark:bg-gray-700 rounded"></div>
          <div class="h-4 w-full bg-gray-200 dark:bg-gray-700 rounded"></div>
        </div>
      </div>
    </section>

    <!-- Actions Skeleton -->
    <section class="space-y-3">
      <div class="h-10 bg-gray-200 dark:bg-gray-700 rounded-md"></div>
      <div class="h-10 bg-gray-200 dark:bg-gray-700 rounded-md"></div>
    </section>
  </div>
</template>
