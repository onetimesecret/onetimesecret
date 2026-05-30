<!-- src/shared/components/closet/TableSkeleton.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="animate-pulse motion-reduce:animate-none">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
    <!-- Header row -->
    <Skeleton
      class="mb-4"
      height="h-12"
      rounded="rounded-t"
      :pulse="false" />
    <!-- Body rows -->
    <Skeleton
      class="mb-2"
      height="h-16"
      rounded="rounded-none"
      :count="3"
      :pulse="false" />
  </div>
</template>
