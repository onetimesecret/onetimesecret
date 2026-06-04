<!-- src/shared/components/closet/ReceiptSkeleton.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="animate-pulse space-y-8 motion-reduce:animate-none">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
    <!-- Secret Link Skeleton (empty block → normalizes gray-100/800 to gray-200/700) -->
    <Skeleton
      height="h-24"
      rounded="rounded-lg"
      :pulse="false" />

    <!-- Status & Timeline Skeleton -->
    <!-- Panel bg (gray-50/gray-800) kept AS-IS: it's a container, not a placeholder
         block. Normalizing it to gray-200/700 would make its nested blocks vanish. -->
    <section class="rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
      <div class="mb-4 flex items-center justify-between">
        <Skeleton
          class="w-24"
          height="h-4"
          :pulse="false" />
        <Skeleton
          class="w-32"
          height="h-6"
          rounded="rounded-full"
          :pulse="false" />
      </div>

      <div class="space-y-6">
        <div
          v-for="n in 3"
          :key="n"
          class="flex gap-4">
          <!-- Avatar circle (size-12 → w-12 h-12) -->
          <Skeleton
            width="w-12"
            height="h-12"
            rounded="rounded-full"
            :pulse="false" />
          <div class="space-y-2">
            <Skeleton
              class="w-32"
              height="h-4"
              :pulse="false" />
            <Skeleton
              class="w-48"
              height="h-3"
              :pulse="false" />
          </div>
        </div>
      </div>
    </section>

    <!-- Instructions Skeleton -->
    <!-- Panel bg (gray-50/gray-800) kept AS-IS for the same container reason. -->
    <section class="space-y-4 rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
      <Skeleton
        class="w-40"
        height="h-4"
        :pulse="false" />
      <div class="space-y-3">
        <div
          v-for="n in 3"
          :key="n"
          class="flex gap-2">
          <!-- Bullet (size-5 → w-5 h-5) -->
          <Skeleton
            width="w-5"
            height="h-5"
            :pulse="false" />
          <!-- w-full sizes the flex item, so it goes on `class`. -->
          <Skeleton
            class="w-full"
            height="h-4"
            :pulse="false" />
        </div>
      </div>
    </section>

    <!-- Actions Skeleton -->
    <section class="space-y-3">
      <Skeleton
        height="h-10"
        rounded="rounded-md"
        :pulse="false" />
      <Skeleton
        height="h-10"
        rounded="rounded-md"
        :pulse="false" />
    </section>
  </div>
</template>
