<!-- src/shared/components/closet/ReceiptSkeleton.vue -->

<template>
  <div class="animate-pulse space-y-8">
    <!-- Secret Link Skeleton -->
    <section class="h-24 rounded-lg bg-gray-100 dark:bg-gray-800"></section>

    <!-- Status & Timeline Skeleton -->
    <section class="rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
      <div class="mb-4 flex items-center justify-between">
        <div class="h-4 w-24 rounded bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-6 w-32 rounded-full bg-gray-200 dark:bg-gray-700"></div>
      </div>

      <div class="space-y-6">
        <div
          v-for="n in 3"
          :key="n"
          class="flex gap-4">
          <div class="size-12 rounded-full bg-gray-200 dark:bg-gray-700"></div>
          <div class="space-y-2">
            <div class="h-4 w-32 rounded bg-gray-200 dark:bg-gray-700"></div>
            <div class="h-3 w-48 rounded bg-gray-200 dark:bg-gray-700"></div>
          </div>
        </div>
      </div>
    </section>

    <!-- Instructions Skeleton -->
    <section class="space-y-4 rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
      <div class="h-4 w-40 rounded bg-gray-200 dark:bg-gray-700"></div>
      <div class="space-y-3">
        <div
          v-for="n in 3"
          :key="n"
          class="flex gap-2">
          <div class="size-5 rounded bg-gray-200 dark:bg-gray-700"></div>
          <div class="h-4 w-full rounded bg-gray-200 dark:bg-gray-700"></div>
        </div>
      </div>
    </section>

    <!-- Actions Skeleton -->
    <section class="space-y-3">
      <div class="h-10 rounded-md bg-gray-200 dark:bg-gray-700"></div>
      <div class="h-10 rounded-md bg-gray-200 dark:bg-gray-700"></div>
    </section>
  </div>
</template>
