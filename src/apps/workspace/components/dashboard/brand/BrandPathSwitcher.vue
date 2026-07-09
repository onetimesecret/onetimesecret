<!-- src/apps/workspace/components/dashboard/brand/BrandPathSwitcher.vue -->

<script setup lang="ts">
  /**
   * The three-way path switcher (Simple / Match my site / Advanced). Selecting a
   * card swaps the left editor panel while the preview column stays fixed.
   * Match and Advanced are selectable so their "coming soon" teasers can be
   * viewed; only Simple is functional.
   */
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { BRAND_PATHS, type BrandPath } from './paths';

  const { t } = useI18n();

  const props = defineProps<{
    modelValue: BrandPath;
  }>();

  const emit = defineEmits<{
    (e: 'update:modelValue', value: BrandPath): void;
  }>();

  const cards = computed(() =>
    BRAND_PATHS.map((path) => ({
      id: path.id,
      name: t(`web.branding.path_${path.id}`),
      tag: t(`web.branding.path_${path.id}_tag`),
      // Only the not-yet-built paths carry a badge ("Coming soon"). The
      // functional Simple path needs no "Default" label.
      badge: path.available ? null : t('web.branding.badge_coming_soon'),
      selected: props.modelValue === path.id,
    }))
  );
</script>

<template>
  <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
    <button
      v-for="card in cards"
      :key="card.id"
      type="button"
      @click="emit('update:modelValue', card.id)"
      :aria-pressed="card.selected"
      class="flex flex-col gap-1 rounded-xl border p-3.5 text-left transition-colors
        hover:border-gray-400"
      :class="card.selected
        ? 'border-2 border-brand-600 bg-brand-50 dark:bg-brand-900/20'
        : 'border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800'">
      <span class="flex items-center gap-2 text-sm font-bold text-gray-900 dark:text-gray-100">
        {{ card.name }}
        <span
          v-if="card.badge"
          class="rounded-full border border-gray-200 bg-gray-50 px-2 py-px text-[10.5px] font-semibold
            text-gray-500 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300">
          {{ card.badge }}
        </span>
      </span>
      <span class="text-xs leading-snug text-gray-500 dark:text-gray-400">{{ card.tag }}</span>
    </button>
  </div>
</template>
