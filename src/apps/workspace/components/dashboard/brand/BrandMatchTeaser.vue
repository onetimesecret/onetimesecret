<!-- src/apps/workspace/components/dashboard/brand/BrandMatchTeaser.vue -->

<script setup lang="ts">
  /**
   * Static, decorative mockup of the "Match my site" path, shown dimmed inside
   * ComingSoonPanel. Illustrative only — no props, no handlers, no i18n (the
   * content is a faded preview of a future feature, not live UI copy).
   */
  import OIcon from '@/shared/components/icons/OIcon.vue';

  // Representative site → page swatch rows.
  const rows = [
    { label: 'Primary', site: '#123C69', page: '#123C69', ok: true },
    { label: 'Accent', site: '#3E7CB1', page: '#3E7CB1', ok: true },
    { label: 'Text', site: '#0B1F33', page: '#1F2937', ok: false },
  ];
</script>

<template>
  <div class="p-[18px]">
    <h2 class="font-brand-slab text-base font-bold text-gray-900 dark:text-gray-100">
      Match my site
    </h2>

    <!-- Read brand from -->
    <div class="mt-3 text-xs font-semibold text-gray-700 dark:text-gray-300">
      Read brand from
    </div>
    <div
      class="mt-1.5 flex items-center gap-2 rounded-lg border border-gray-300
        px-3 py-2 dark:border-gray-600">
      <OIcon
        collection="mdi"
        name="web"
        class="size-4 text-gray-400" />
      <span class="font-mono text-sm text-gray-900 dark:text-gray-200">https://example.com</span>
      <span class="ml-auto text-xs font-medium text-brand-600">Read again</span>
    </div>

    <!-- What we read -->
    <div class="mt-3 overflow-hidden rounded-lg border border-gray-200 dark:border-gray-700">
      <div
        class="border-b border-gray-200 bg-gray-100 px-3 py-1.5 text-[10.5px] font-semibold
          tracking-wide text-gray-500 uppercase dark:border-gray-700 dark:bg-gray-700 dark:text-gray-300">
        What we read from your site
      </div>
      <div class="divide-y divide-gray-100 dark:divide-gray-700">
        <div
          v-for="row in rows"
          :key="row.label"
          class="grid grid-cols-[70px_1fr_16px_1fr_auto] items-center gap-2 px-3 py-1.5">
          <span class="text-xs text-gray-500">{{ row.label }}</span>
          <span class="flex items-center gap-1.5">
            <span
              class="size-3.5 rounded-full ring-1 ring-gray-200"
              :style="{ background: row.site }"></span>
            <span class="font-mono text-[11px] text-gray-800 dark:text-gray-300">{{ row.site }}</span>
          </span>
          <span class="text-center text-xs text-gray-300">→</span>
          <span class="flex items-center gap-1.5">
            <span
              class="size-3.5 rounded-full ring-1 ring-gray-200"
              :style="{ background: row.page }"></span>
            <span class="font-mono text-[11px] text-gray-800 dark:text-gray-300">{{ row.page }}</span>
          </span>
          <span
            class="justify-self-end text-[11px] font-medium"
            :class="row.ok ? 'text-emerald-600' : 'text-amber-600'">
            {{ row.ok ? 'Match' : 'Differs' }}
          </span>
        </div>
      </div>
    </div>

    <div
      class="mt-3 flex h-10 items-center justify-center rounded-lg bg-brand-600
        text-sm font-medium text-white">
      Match my site
    </div>
  </div>
</template>
