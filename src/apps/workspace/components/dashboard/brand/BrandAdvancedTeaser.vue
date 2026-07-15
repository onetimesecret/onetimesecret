<!-- src/apps/workspace/components/dashboard/brand/BrandAdvancedTeaser.vue -->

<script setup lang="ts">
  /**
   * Static, decorative mockup of the "Advanced" path (a Tailwind v4 @theme
   * editor), shown dimmed inside ComingSoonPanel. Illustrative only.
   */
  import OIcon from '@/shared/components/icons/OIcon.vue';

  const lines = [
    { prop: '--color-primary', val: '#4F46E5', swatch: '#4F46E5' },
    { prop: '--color-secondary', val: '#0EA5E9', swatch: '#0EA5E9' },
    { prop: '--color-text', val: '#1F2937', swatch: '#1F2937' },
    { prop: '--radius-brand', val: '0.5rem', swatch: null },
  ];
</script>

<template>
  <div class="p-[18px]">
    <div class="flex items-center gap-2">
      <h2 class="font-brand-slab text-base font-bold text-gray-900 dark:text-gray-100">
        Custom stylesheet
      </h2>
      <span
        class="rounded-full border border-gray-200 bg-gray-50 px-2 py-0.5 text-[10.5px]
          font-semibold text-gray-500 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300">
        Tailwind v4
      </span>
    </div>

    <!-- @theme code block -->
    <div class="mt-3 rounded-lg bg-slate-900 px-4 py-3.5 font-mono text-xs leading-relaxed">
      <div class="text-sky-300">
        @theme {
      </div>
      <div
        v-for="line in lines"
        :key="line.prop"
        class="flex items-center gap-2 pl-4">
        <span class="text-blue-300">{{ line.prop }}</span><span class="text-slate-500">:</span>
        <span
          v-if="line.swatch"
          class="size-2.5 rounded-sm"
          :style="{ background: line.swatch }"></span>
        <span class="text-amber-300">{{ line.val }}</span><span class="text-slate-500">;</span>
      </div>
      <div class="text-sky-300">
        }
      </div>
    </div>

    <div class="mt-3 flex gap-2">
      <span
        class="inline-flex h-9 items-center gap-1.5 rounded-lg border border-gray-200
          px-3 text-xs font-medium text-gray-700 dark:border-gray-600 dark:text-gray-300">
        <OIcon
          collection="mdi"
          name="content-copy"
          class="size-3.5" />
        Copy tokens
      </span>
      <span
        class="inline-flex h-9 items-center gap-1.5 rounded-lg border border-gray-200
          px-3 text-xs font-medium text-gray-700 dark:border-gray-600 dark:text-gray-300">
        <OIcon
          collection="mdi"
          name="upload"
          class="size-3.5" />
        Import .css
      </span>
    </div>
  </div>
</template>
