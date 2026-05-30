<!-- src/shared/components/closet/ListSkeleton.vue -->

<script setup lang="ts">
  /**
   * ListSkeleton
   *
   * Loading placeholder for the list archetype in #3269: active sessions,
   * SSO domains, organizations, passkeys, pending invitations. (The members
   * list renders a real `<table>`, so it uses TableSkeleton, not this.)
   *
   * Each row mirrors the shape those lists share: an optional leading
   * icon/avatar block, a growing text column (a primary label line over a
   * shorter secondary line), and a small trailing action block on the right.
   *
   * Icon-led rows (passkeys, SSO domains, members) start with a small icon or
   * a circular avatar. Toggle the leading block with `icon`, and size/shape it
   * with `iconSize` (a `w-N`/`h-N` value applied to both axes) and
   * `iconRounded`. Text-led rows (organizations) leave `icon` off (default).
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
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  interface Props {
    /** Number of list rows to render. */
    count?: number;
    /** Render a leading icon/avatar block on each row. */
    icon?: boolean;
    /**
     * Width utility for the leading block, also applied as its height (square
     * footprint), e.g. 'w-5' → a 5×5 icon, 'w-10' → a 10×10 avatar.
     */
    iconSize?: string;
    /** Corner utility for the leading block, e.g. 'rounded-full' for avatars. */
    iconRounded?: string;
  }

  const props = withDefaults(defineProps<Props>(), {
    count: 3,
    icon: false,
    iconSize: 'w-5',
    iconRounded: 'rounded',
  });

  /** Derive the height utility from iconSize (w-N → h-N) for a square block. */
  const iconHeight = computed(() => props.iconSize.replace(/\bw-/g, 'h-'));

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
      <!-- Optional leading icon/avatar block. Width AND height are set so the
           primitive's w-full/h-4 defaults don't leak onto the square block. -->
      <Skeleton
        v-if="icon"
        :width="iconSize"
        :height="iconHeight"
        :rounded="iconRounded"
        :pulse="false" />
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
