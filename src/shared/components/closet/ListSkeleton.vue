<!-- src/shared/components/closet/ListSkeleton.vue -->

<script setup lang="ts">
  /**
   * ListSkeleton
   *
   * Loading placeholder for the list archetype (5 TARGET sites in #3269:
   * members, active sessions, domains, organizations, pending invitations).
   *
   * Each row mirrors the shape those lists share: a growing left text column
   * (a primary label line over a shorter secondary line) and a small trailing
   * action block on the right.
   *
   * Per the primitive gotcha (decisions rule 7), we emit our own `v-for` rows
   * instead of the primitive's `count` prop — `count` only reproduces a flat
   * run of identical blocks at `space-y-2`, not a structured row. For the same
   * reason, the growing text column is sized with `flex-1` on the row markup,
   * never via the Skeleton `width` prop.
   *
   * a11y: the wrapper is the busy status region with an sr-only loading label
   * and owns the single pulse; children pass `:pulse="false"`.
   */
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  interface Props {
    /** Number of list rows to render. */
    count?: number;
  }

  withDefaults(defineProps<Props>(), {
    count: 3,
  });

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="animate-pulse space-y-3 motion-reduce:animate-none">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>

    <div
      v-for="n in count"
      :key="n"
      class="flex items-center justify-between gap-4 rounded-md px-4 py-3">
      <!-- Growing text column: primary line over a shorter secondary line.
           flex-1 sizes the row item, so it lives on the wrapper class. -->
      <div class="flex-1 space-y-2">
        <Skeleton
          width="w-1/3"
          height="h-4"
          :pulse="false" />
        <Skeleton
          width="w-1/4"
          height="h-3"
          :pulse="false" />
      </div>
      <!-- Trailing action block. -->
      <Skeleton
        class="w-16"
        height="h-8"
        rounded="rounded-md"
        :pulse="false" />
    </div>
  </div>
</template>
