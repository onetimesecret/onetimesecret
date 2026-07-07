<!-- src/apps/admin/components/kit/StatCard.vue -->

<script setup lang="ts">
  import { computed } from 'vue';

  import OIcon from '@/shared/components/icons/OIcon.vue';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

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
  <component
    :is="to ? 'router-link' : 'div'"
    :to="to"
    :data-testid="testid"
    class="flex items-start gap-4 rounded-lg border border-gray-200 bg-white p-4 shadow-sm transition-shadow dark:border-gray-800 dark:bg-gray-800"
    :class="to ? 'hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500' : ''">
    <span
      v-if="icon || $slots.icon"
      class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-900/20 dark:text-brand-400">
      <slot name="icon">
        <OIcon
          :collection="iconCollection"
          :name="icon!"
          size="6" />
      </slot>
    </span>

    <div class="min-w-0 flex-1">
      <p class="truncate text-sm font-medium text-gray-500 dark:text-gray-400">
        {{ label }}
      </p>

      <Skeleton
        v-if="loading"
        class="mt-2"
        height="h-7"
        width="w-20"
        :pulse="true" />
      <p
        v-else
        class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">
        <slot>{{ value }}</slot>
      </p>

      <p
        v-if="trend && !loading"
        class="mt-1 text-xs font-medium"
        :class="trendClass">
        {{ trend }}
      </p>

      <slot name="footer"></slot>
    </div>
  </component>
</template>
