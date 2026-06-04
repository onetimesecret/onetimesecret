<!-- src/shared/components/closet/SecretSkeleton.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  const { t } = useI18n();
</script>

<template>
  <!-- Main Content Box -->
  <!-- The status/sr-only live on the static outer container; the pulse stays
       on the inner wrapper so the border does not animate. -->
  <div
    role="status"
    aria-busy="true"
    class="rounded-lg border border-gray-200 p-6 dark:border-gray-700">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
    <!-- Pulse wrapper (border stays static, matching the other skeletons) -->
    <div class="animate-pulse motion-reduce:animate-none">
      <!-- Secret Info Line -->
      <Skeleton
        class="mb-4"
        height="h-6"
        width="w-2/3"
        rounded="rounded-lg"
        :pulse="false" />

      <!-- Form/Content Area -->
      <div class="space-y-4">
        <Skeleton
          height="h-12"
          rounded="rounded-lg"
          :pulse="false" />
        <Skeleton
          height="h-12"
          rounded="rounded-lg"
          :pulse="false" />
      </div>
    </div>
  </div>
</template>
