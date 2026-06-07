<!-- src/apps/workspace/dashboard/DashboardSkeleton.vue -->

<!-- Loading skeleton that mimics dashboard layout without content -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="container mx-auto min-w-[320px] max-w-2xl animate-pulse motion-reduce:animate-none">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
    <!-- Secret Form Skeleton -->
    <div class="mb-10 space-y-4">
      <!-- Textarea placeholder -->
      <Skeleton
        height="h-32"
        rounded="rounded-lg"
        :pulse="false" />

      <!-- Options row placeholder -->
      <!-- w-1/3 sizes the flex item (Skeleton's root), so it goes on `class`. -->
      <div class="flex gap-4">
        <Skeleton
          class="w-1/3"
          height="h-10"
          rounded="rounded-lg"
          :pulse="false" />
        <Skeleton
          class="w-1/3"
          height="h-10"
          rounded="rounded-lg"
          :pulse="false" />
      </div>

      <!-- Button placeholder (was gray-300/600 → normalizes to gray-200/700) -->
      <Skeleton
        height="h-12"
        rounded="rounded-lg"
        :pulse="false" />
    </div>

    <!-- Teams Section Skeleton (optional, appears for team-capable users) -->
    <div class="mb-10 space-y-4">
      <!-- Section header -->
      <div class="flex items-center justify-between">
        <Skeleton
          class="w-32"
          height="h-6"
          :pulse="false" />
        <Skeleton
          class="w-20"
          height="h-4"
          :pulse="false" />
      </div>

      <!-- Team cards grid -->
      <div class="grid gap-4 sm:grid-cols-2">
        <Skeleton
          height="h-24"
          rounded="rounded-lg"
          :pulse="false" />
        <Skeleton
          height="h-24"
          rounded="rounded-lg"
          :pulse="false" />
      </div>
    </div>
  </div>
</template>
