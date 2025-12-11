<!-- src/apps/workspace/dashboard/DashboardSkeleton.vue -->

<!-- Loading skeleton that mimics dashboard layout without content -->

<script setup lang="ts">
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl animate-pulse">
    <!-- Secret Form Skeleton -->
    <div class="mb-12 space-y-4">
      <!-- Textarea placeholder -->
      <div class="h-32 rounded-lg bg-gray-200 dark:bg-gray-700"></div>

      <!-- Options row placeholder -->
      <div class="flex gap-4">
        <div class="h-10 w-1/3 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-10 w-1/3 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      </div>

      <!-- Button placeholder -->
      <div class="h-12 w-full rounded-lg bg-gray-300 dark:bg-gray-600"></div>
    </div>

    <!-- Teams Section Skeleton (optional, appears for team-capable users) -->
    <div class="mb-12 space-y-4">
      <!-- Section header -->
      <div class="flex items-center justify-between">
        <div class="h-6 w-32 rounded bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-4 w-20 rounded bg-gray-200 dark:bg-gray-700"></div>
      </div>

      <!-- Team cards grid -->
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="h-24 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-24 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      </div>
    </div>
  </div>
</template>
