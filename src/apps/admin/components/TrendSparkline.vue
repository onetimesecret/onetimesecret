<!-- src/apps/admin/components/TrendSparkline.vue -->

<script setup lang="ts">
  import { computed } from 'vue';

  import type { ColonelTrendPoint } from '@/schemas/api/account/responses/colonel-trends';

  /**
   * Inline SVG sparkline for the overview trend cards (observability lane).
   *
   * A presentational leaf, single-series by design (one metric per card, so no
   * legend — the card label names the series). Follows the house mark specs:
   * 2px round-capped line, an area wash at 10% opacity, and an 8px end marker
   * carrying a 2px surface ring. The line inherits `currentColor`, so the
   * OWNER picks the hue (and its dark-mode step) with text utility classes.
   * Each day gets a full-height transparent hover band with a native SVG
   * `<title>` tooltip ("YYYY-MM-DD: n"), and the whole figure exposes the
   * caller's `aria-label` summary for screen readers.
   */
  const props = defineProps<{
    /** Day buckets, oldest first (zero-filled server-side). */
    points: ColonelTrendPoint[];
    /** Accessible summary of the series (label + latest value); applied as
     *  the figure's `aria-label`. */
    label: string;
    /** Test id applied to the svg root. */
    testid?: string;
  }>();

  // Fixed drawing space; the svg scales to its container (uniform, so the end
  // marker stays round; `vector-effect` keeps the line at 2px regardless).
  const WIDTH = 240;
  const HEIGHT = 56;
  const PAD_X = 5;
  const PAD_TOP = 6;
  const BASELINE = HEIGHT - 3;

  const maxCount = computed(() =>
    Math.max(...props.points.map((point) => point.count), 1)
  );

  const coords = computed(() => {
    const n = props.points.length;
    if (n === 0) return [];
    const span = WIDTH - PAD_X * 2;
    return props.points.map((point, index) => ({
      x: n === 1 ? WIDTH / 2 : PAD_X + (index * span) / (n - 1),
      y: PAD_TOP + (1 - point.count / maxCount.value) * (BASELINE - PAD_TOP),
      point,
    }));
  });

  const linePath = computed(() =>
    coords.value
      .map((c, index) => `${index === 0 ? 'M' : 'L'}${c.x.toFixed(2)},${c.y.toFixed(2)}`)
      .join(' ')
  );

  const areaPath = computed(() => {
    if (coords.value.length < 2) return '';
    const first = coords.value[0];
    const last = coords.value[coords.value.length - 1];
    return `${linePath.value} L${last.x.toFixed(2)},${BASELINE} L${first.x.toFixed(2)},${BASELINE} Z`;
  });

  const endMarker = computed(() => coords.value[coords.value.length - 1] ?? null);

  /** Full-height hover band per day — a hit target far bigger than the mark. */
  const bandWidth = computed(() =>
    coords.value.length > 1 ? (WIDTH - PAD_X * 2) / (coords.value.length - 1) : WIDTH
  );
</script>

<template>
  <svg
    :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
    class="block w-full"
    role="img"
    :aria-label="label"
    :data-testid="testid">
    <!-- Area wash: the series hue at 10% — a wash, never a saturated block. -->
    <path
      v-if="areaPath"
      :d="areaPath"
      fill="currentColor"
      fill-opacity="0.1"
      stroke="none" />

    <!-- The line: 2px, round join/cap, non-scaling so it stays 2px. -->
    <path
      v-if="coords.length > 1"
      :d="linePath"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      vector-effect="non-scaling-stroke" />

    <!-- End marker (today): >= 8px, with a 2px surface ring so it stays
         legible where it sits on the line. Ring = the card surface color. -->
    <circle
      v-if="endMarker"
      :cx="endMarker.x"
      :cy="endMarker.y"
      r="4"
      fill="currentColor"
      stroke-width="2"
      class="stroke-white dark:stroke-gray-800" />

    <!-- Hover layer: one transparent full-height band per day, native SVG
         tooltip carrying the exact date + value (the "table view" per point). -->
    <g>
      <rect
        v-for="c in coords"
        :key="c.point.date"
        :x="c.x - bandWidth / 2"
        y="0"
        :width="bandWidth"
        :height="HEIGHT"
        fill="transparent"
        :data-date="c.point.date">
        <title>{{ c.point.date }}: {{ c.point.count }}</title>
      </rect>
    </g>
  </svg>
</template>
