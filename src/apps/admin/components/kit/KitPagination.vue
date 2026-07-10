<!-- src/apps/admin/components/kit/KitPagination.vue -->

<script setup lang="ts">
  import type { PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Admin-bundle pagination control (ticket #11, CONTRACT 5).
   *
   * Re-homes the legacy `ColonelPagination` emit contract
   * (`update:page` / `update:perPage`, over the frozen
   * `page` / `per_page` / `total_count` / `total_pages` envelope) into
   * `src/apps/admin/components/kit/` so the admin bundle never imports the
   * retiring `src/apps/colonel/` tree.
   *
   * The `pagination` prop is exactly the {@link PageMeta} the shared
   * `usePaginatedFetch` composable already produces, so a resource view wires
   * store → control with no re-mapping. Existing `web.colonel.pagination.*`
   * strings are reused verbatim (CONTRACT 1 — reuse over re-creation).
   */
  const props = defineProps<{
    /** The server's pagination envelope for the current page. */
    pagination: PageMeta;
    /** Disables navigation while a page request is in flight. */
    loading?: boolean;
    /** Per-page choices offered in the selector. */
    perPageOptions?: number[];
  }>();

  const emit = defineEmits<{
    'update:page': [page: number];
    'update:perPage': [perPage: number];
  }>();

  const { t } = useI18n();

  const perPageChoices = computed(() => props.perPageOptions ?? [25, 50, 100]);

  const rangeStart = computed(() => {
    if (props.pagination.total_count === 0) return 0;
    return (props.pagination.page - 1) * props.pagination.per_page + 1;
  });

  const rangeEnd = computed(() => {
    const end = props.pagination.page * props.pagination.per_page;
    return Math.min(end, props.pagination.total_count);
  });

  const canGoPrev = computed(() => props.pagination.page > 1);
  const canGoNext = computed(() => props.pagination.page < props.pagination.total_pages);

  function handlePrev(): void {
    if (canGoPrev.value && !props.loading) {
      emit('update:page', props.pagination.page - 1);
    }
  }

  function handleNext(): void {
    if (canGoNext.value && !props.loading) {
      emit('update:page', props.pagination.page + 1);
    }
  }

  function handlePerPageChange(event: Event): void {
    const target = event.target as HTMLSelectElement;
    emit('update:perPage', Number(target.value));
  }
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-between gap-4 text-sm text-gray-600 dark:text-gray-400">
    <!-- Summary -->
    <div class="tabular-nums">
      {{
        t('web.colonel.pagination.showing', {
          start: rangeStart,
          end: rangeEnd,
          total: pagination.total_count,
        })
      }}
    </div>

    <div class="flex items-center gap-4">
      <!-- Per-page selector (native <select> for accessibility) -->
      <div class="flex items-center gap-2">
        <label
          for="kit-per-page-select"
          class="sr-only">
          {{ t('web.colonel.pagination.itemsPerPage') }}
        </label>
        <select
          id="kit-per-page-select"
          :value="pagination.per_page"
          :disabled="loading"
          class="rounded border border-gray-300 bg-white px-2 py-1 text-sm text-gray-700 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300"
          @change="handlePerPageChange">
          <option
            v-for="option in perPageChoices"
            :key="option"
            :value="option">
            {{ t('web.colonel.pagination.perPage', { count: option }) }}
          </option>
        </select>
      </div>

      <!-- Page indicator -->
      <div class="tabular-nums">
        {{
          t('web.colonel.pagination.pageOf', {
            current: pagination.page,
            total: pagination.total_pages,
          })
        }}
      </div>

      <!-- Navigation buttons -->
      <div class="flex gap-1">
        <button
          type="button"
          :disabled="!canGoPrev || loading"
          class="rounded-md border border-gray-300 px-3 py-1 font-medium text-gray-700 transition-colors hover:border-brand-400 hover:bg-brand-50/50 hover:text-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-gray-300 disabled:hover:bg-transparent disabled:hover:text-gray-700 dark:border-gray-600 dark:text-gray-300 dark:hover:border-brand-500/60 dark:hover:bg-brand-500/10 dark:hover:text-brand-200"
          @click="handlePrev">
          {{ t('web.COMMON.previous') }}
        </button>
        <button
          type="button"
          :disabled="!canGoNext || loading"
          class="rounded-md border border-gray-300 px-3 py-1 font-medium text-gray-700 transition-colors hover:border-brand-400 hover:bg-brand-50/50 hover:text-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-gray-300 disabled:hover:bg-transparent disabled:hover:text-gray-700 dark:border-gray-600 dark:text-gray-300 dark:hover:border-brand-500/60 dark:hover:bg-brand-500/10 dark:hover:text-brand-200"
          @click="handleNext">
          {{ t('web.COMMON.next') }}
        </button>
      </div>
    </div>
  </div>
</template>
