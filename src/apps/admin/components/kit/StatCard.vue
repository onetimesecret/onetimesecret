<!-- src/apps/admin/components/kit/StatCard.vue -->

<script setup lang="ts">
  import Skeleton from '@/shared/components/closet/Skeleton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed } from 'vue';

  /**
   * Dashboard metric tile for the admin console (ticket #11).
   *
   * A presentational leaf: the caller passes an already-translated `label` and a
   * `value`, and optionally an icon + a trend delta. Loading renders the shared
   * `Skeleton` rather than a bespoke placeholder. When `to` is set the whole tile
   * becomes a `<router-link>`; otherwise it renders as a plain `<div>`.
   */
  const props = withDefaults(
    defineProps<{
      /** Metric caption (already translated). */
      label: string;
      /** Metric value. Numbers are rendered as-is; format upstream if needed. */
      value?: string | number;
      /** Optional icon name within `iconCollection`. */
      icon?: string;
      /** Icon collection for {@link OIcon}. Defaults to heroicons. */
      iconCollection?: string;
      /** Optional signed delta, e.g. '+12%'. */
      trend?: string;
      /** Direction of `trend`, controlling its colour. */
      trendDirection?: 'up' | 'down' | 'neutral';
      /** Shows a skeleton in place of the value while true. */
      loading?: boolean;
      /** When set, the tile is a router-link to this target. */
      to?: string;
      /** Test id applied to the tile root. */
      testid?: string;
    }>(),
    {
      value: undefined,
      icon: undefined,
      iconCollection: 'heroicons',
      trend: undefined,
      trendDirection: 'neutral',
      loading: false,
      to: undefined,
      testid: undefined,
    }
  );

  const trendClass = computed(() => {
    switch (props.trendDirection) {
      case 'up':
        return 'text-green-600 dark:text-green-400';
      case 'down':
        return 'text-red-600 dark:text-red-400';
      default:
        return 'text-gray-500 dark:text-gray-400';
    }
  });
</script>

<template>
  <!-- Ledger "field card": a tracked slab eyebrow (with a small inline glyph)
       over a full-width slab value. Icon lives inline with the caption rather
       than in a left tile, so the value owns the whole card width and long text
       like "Colonel" no longer clips. -->
  <component
    :is="to ? 'router-link' : 'div'"
    :to="to"
    :data-testid="testid"
    class="block rounded-lg border border-gray-200 bg-white p-4 transition-colors dark:border-gray-800 dark:bg-gray-900"
    :class="
      to
        ? 'hover:border-brand-400 hover:bg-brand-50/40 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:hover:border-brand-500/60 dark:hover:bg-brand-500/5'
        : ''
    ">
    <div class="flex items-center gap-2 text-gray-500 dark:text-gray-400">
      <span
        v-if="icon || $slots.icon"
        class="flex size-6 shrink-0 items-center justify-center rounded bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
        <slot name="icon">
          <OIcon
            :collection="iconCollection"
            :name="icon!"
            size="4" />
        </slot>
      </span>
      <p
        class="min-w-0 truncate font-brand text-[11px] font-semibold tracking-[0.12em] uppercase">
        {{ label }}
      </p>
    </div>

    <Skeleton
      v-if="loading"
      class="mt-3"
      height="h-7"
      width="w-20"
      :pulse="true" />
    <p
      v-else
      class="mt-2 font-brand text-xl leading-tight font-bold break-words text-gray-900 tabular-nums dark:text-white">
      <slot>{{ value }}</slot>
    </p>

    <p
      v-if="trend && !loading"
      class="mt-1.5 text-xs font-medium tabular-nums"
      :class="trendClass">
      {{ trend }}
    </p>

    <slot name="footer"></slot>
  </component>
</template>
