<!-- src/shared/components/closet/Skeleton.vue -->

<script setup lang="ts">
  /**
   * Skeleton
   *
   * Foundational loading-placeholder primitive. Renders one or more
   * decorative gray blocks. It is intentionally a "dumb" block: it carries
   * no `role="status"`, `aria-busy`, or `sr-only` text — those announcements
   * belong to the composite skeletons / usage sites that arrange these blocks.
   *
   * Reduced motion: when `pulse` is true the wrapper uses
   * `animate-pulse motion-reduce:animate-none`, so users with
   * `prefers-reduced-motion: reduce` see a static gray block (still reads as a
   * placeholder) instead of a pulsing one.
   */
  interface Props {
    /** Tailwind width utility, e.g. 'w-2/3'. */
    width?: string;
    /** Tailwind height utility, e.g. 'h-6'. */
    height?: string;
    /** Tailwind corner utility: 'rounded' | 'rounded-lg' | 'rounded-full'. */
    rounded?: string;
    /** Number of identical rows to repeat. */
    count?: number;
    /**
     * Wrap the blocks in `animate-pulse`. Set to false when a parent element
     * already drives the pulse animation (avoids double-animating).
     */
    pulse?: boolean;
  }

  withDefaults(defineProps<Props>(), {
    width: 'w-full',
    height: 'h-4',
    rounded: 'rounded',
    count: 1,
    pulse: false,
  });
</script>

<template>
  <div
    :class="pulse && 'animate-pulse motion-reduce:animate-none'"
    class="space-y-2">
    <div
      v-for="n in count"
      :key="n"
      aria-hidden="true"
      :class="[width, height, rounded]"
      class="bg-gray-200 dark:bg-gray-700"></div>
  </div>
</template>
