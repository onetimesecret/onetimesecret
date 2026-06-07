<!-- src/shared/components/closet/CardGridSkeleton.vue -->

<script setup lang="ts">
  /**
   * CardGridSkeleton
   *
   * Loading placeholder for the card-grid archetype (3 TARGET sites in #3269:
   * pricing plan cards, plan selector, plan preview modal).
   *
   * Renders a responsive grid of equal card blocks (`sm:grid-cols-2`, matching
   * the dashboard team grid). The column count is fixed, not a prop: Tailwind's
   * JIT only generates classes it can see as complete literals, so an
   * interpolated `sm:grid-cols-${n}` would silently fail to produce CSS.
   *
   * Per the primitive gotcha (decisions rule 7), cards are emitted with our own
   * `v-for`, not the primitive's `count` prop (which would stack flat blocks in
   * a single column rather than fill grid cells).
   *
   * a11y: the wrapper is the busy status region with an sr-only loading label
   * and owns the single pulse; child cards pass `:pulse="false"`.
   */
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  interface Props {
    /** Number of card blocks to render in the grid. */
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
    class="grid animate-pulse gap-4 motion-reduce:animate-none sm:grid-cols-2">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>

    <Skeleton
      v-for="n in count"
      :key="n"
      height="h-40"
      rounded="rounded-lg"
      :pulse="false" />
  </div>
</template>
