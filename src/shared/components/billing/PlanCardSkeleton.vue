<!-- src/shared/components/billing/PlanCardSkeleton.vue -->

<script setup lang="ts">
  /**
   * PlanCardSkeleton
   *
   * Loading placeholder for the billing "Select a Plan" grid (#3269). Mirrors
   * the geometry of PlanCard.vue (title, big price + "/month", a "Features"
   * label over a checklist, and a full-width footer button separated by a top
   * border) so the load→loaded transition has no layout jump.
   *
   * The whole grid is reproduced: the outer wrapper matches PlanSelector's live
   * grid (`mx-auto flex max-w-[1600px] flex-wrap justify-center gap-6`), and
   * each card sits in `<div class="flex w-full max-w-sm">`, identical to the
   * real cards so widths line up exactly.
   *
   * Per the primitive gotcha (decisions rule 7), we emit our own `v-for` rows
   * instead of the primitive's `count` prop for structured markup. Relative
   * widths inside flex rows (the feature text lines) are applied via `class=`
   * on the Skeleton — a relative `width` prop would size the inner block against
   * a shrink-wrapped flex item and collapse to zero. Fixed widths (price blocks,
   * stacked block-context blocks) use the `width` prop directly.
   *
   * a11y: the outermost wrapper is the busy status region with an sr-only
   * loading label and owns the single pulse; every child passes `:pulse="false"`.
   */
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  interface Props {
    /** Number of card skeletons to render. */
    count?: number;
  }

  withDefaults(defineProps<Props>(), {
    count: 2,
  });

  /** Varied feature text-line widths so the checklist reads as real copy. */
  const featureWidths = ['w-3/4', 'w-2/3', 'w-1/2', 'w-3/5', 'w-2/3'];

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="mx-auto flex max-w-[1600px] flex-wrap justify-center gap-6 animate-pulse motion-reduce:animate-none">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>

    <div
      v-for="n in count"
      :key="n"
      class="flex w-full max-w-sm">
      <!-- Card root: mirrors PlanCard's default (non-highlighted) outer card. -->
      <div
        class="relative flex w-full flex-col rounded-2xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div class="flex-1 p-6">
          <!-- Header: plan title -->
          <div class="mb-4">
            <Skeleton
              width="w-1/2"
              height="h-6"
              :pulse="false" />
          </div>

          <!-- Price: large amount + small "/month" on a baseline row -->
          <div class="mb-6">
            <div class="flex items-baseline gap-2">
              <Skeleton
                width="w-32"
                height="h-10"
                :pulse="false" />
              <Skeleton
                width="w-16"
                height="h-4"
                :pulse="false" />
            </div>
          </div>

          <!-- Features: label over a checklist of icon + text-line rows -->
          <div class="space-y-3">
            <Skeleton
              width="w-24"
              height="h-4"
              :pulse="false" />

            <ul class="space-y-2">
              <li
                v-for="(featureWidth, i) in featureWidths"
                :key="i"
                class="flex items-start gap-2">
                <!-- Fixed-size square check-icon block (size-5). -->
                <Skeleton
                  width="w-5"
                  height="h-5"
                  rounded="rounded-none"
                  :pulse="false" />
                <!-- Relative-width text line: width on class (flex item). -->
                <Skeleton
                  :class="featureWidth"
                  height="h-4"
                  :pulse="false" />
              </li>
            </ul>
          </div>
        </div>

        <!-- Footer: full-width action button, separated by a top border. -->
        <div class="border-t border-gray-200 p-6 dark:border-gray-700">
          <Skeleton
            width="w-full"
            height="h-9"
            rounded="rounded-md"
            :pulse="false" />
        </div>
      </div>
    </div>
  </div>
</template>
