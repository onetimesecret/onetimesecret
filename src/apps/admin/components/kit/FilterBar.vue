<!-- src/apps/admin/components/kit/FilterBar.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import type { FilterConfig } from './types';

  /**
   * Filter toolbar for admin list views (ticket #11).
   *
   * Replaces the inline, per-view filter `<select>`s (e.g. the duplicated
   * `<select>` blocks in ColonelOrganizations.vue) with a config-driven bar.
   * Each {@link FilterConfig} renders a NATIVE `<select>` — accessibility depends
   * on native semantics (see #11 notes) — and the bar is fully controlled: the
   * owner holds every value and updates it from the `filter-change` event.
   *
   * An optional search box (`v-model:search`) and a "clear" affordance round
   * out the bar. Extra bespoke controls can be dropped into the default slot; a
   * trailing actions slot hosts view-level buttons.
   *
   * The search box NEVER fetches on its own. Typing only updates the bound
   * text; the owner runs the search when the bar emits `submit` (Enter or the
   * search button). Every admin list search is a bounded-but-real index scan
   * on the server, and the earlier per-keystroke debounce turned one operator
   * typing an address into a burst of concurrent scans. While the owner has a
   * request in flight (`busy`), the bar refuses to emit another `submit`, so
   * hammering Enter cannot queue a burst either. The input itself is disabled
   * while `busy` too: the term cannot change mid-flight, so the results that
   * land can never sit under a different visible query than the one searched.
   */
  const props = withDefaults(
    defineProps<{
      /** Declarative filter controls. Rendered left-to-right. */
      filters?: FilterConfig[];
      /** Current search text (use with `v-model:search`). */
      search?: string;
      /** Placeholder for the search box. */
      searchPlaceholder?: string;
      /** Show the search box. Defaults to true. */
      showSearch?: boolean;
      /** Show the "clear filters" button. Defaults to true. */
      showClear?: boolean;
      /**
       * Whether any filter/search is currently active. Controls whether the
       * clear button is enabled. Owner-computed so the bar stays stateless.
       */
      hasActiveFilters?: boolean;
      /** Test id applied to the bar root. */
      testid?: string;
      /**
       * A search request is in flight. Disables the search button and
       * suppresses Enter so at most one search runs at a time.
       */
      busy?: boolean;
    }>(),
    {
      filters: () => [],
      search: '',
      searchPlaceholder: undefined,
      showSearch: true,
      showClear: true,
      hasActiveFilters: false,
      testid: undefined,
      busy: false,
    }
  );

  const emit = defineEmits<{
    /** Two-way binding for the search text. */
    'update:search': [value: string];
    /** A filter select changed: (filter key, new value). */
    'filter-change': [key: string, value: string];
    /** The clear affordance was activated. */
    clear: [];
    /** The search was submitted (Enter key or the search button). */
    submit: [];
  }>();

  const { t } = useI18n();

  const resolvedSearchPlaceholder = computed(
    () => props.searchPlaceholder ?? t('web.admin.kit.filterBar.searchPlaceholder')
  );

  function onSearchInput(event: Event): void {
    emit('update:search', (event.target as HTMLInputElement).value);
  }

  function onSearchKeydown(event: KeyboardEvent): void {
    if (event.key === 'Enter') {
      event.preventDefault();
      if (!props.busy) emit('submit');
    }
  }

  function onSearchClick(): void {
    if (!props.busy) emit('submit');
  }

  function onFilterChange(config: FilterConfig, event: Event): void {
    emit('filter-change', config.key, (event.target as HTMLSelectElement).value);
  }
</script>

<template>
  <div
    :data-testid="testid"
    class="flex flex-wrap items-end gap-3">
    <!-- Search box -->
    <div
      v-if="showSearch"
      class="min-w-0 flex-1">
      <label
        for="kit-filter-search"
        class="sr-only">
        {{ t('web.admin.kit.filterBar.search') }}
      </label>
      <div class="flex gap-2">
        <div class="relative min-w-0 flex-1">
          <span
            class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-gray-400 dark:text-gray-500">
            <OIcon
              collection="heroicons"
              name="magnifying-glass"
              size="5" />
          </span>
          <input
            id="kit-filter-search"
            type="search"
            :value="search"
            :placeholder="resolvedSearchPlaceholder"
            :disabled="busy"
            :aria-busy="busy"
            class="block w-full rounded-md border border-gray-300 py-2 pr-3 pl-10 text-sm placeholder:text-gray-400 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:placeholder:text-gray-500"
            @input="onSearchInput"
            @keydown="onSearchKeydown" />
        </div>
        <button
          type="button"
          :disabled="busy"
          :aria-busy="busy"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="onSearchClick">
          <OIcon
            collection="heroicons"
            name="magnifying-glass"
            size="4" />
          {{ t('web.admin.kit.filterBar.searchSubmit') }}
        </button>
      </div>
    </div>

    <!-- Declarative filter selects -->
    <div
      v-for="config in filters"
      :key="config.key"
      class="flex flex-col gap-1">
      <label
        :for="`kit-filter-${config.key}`"
        class="font-brand text-[11px] font-semibold tracking-[0.1em] text-gray-500 uppercase dark:text-gray-400">
        {{ config.label }}
      </label>
      <select
        :id="`kit-filter-${config.key}`"
        :value="config.value ?? ''"
        class="rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300"
        @change="onFilterChange(config, $event)">
        <option value="">
          {{ config.allLabel ?? t('web.admin.kit.filterBar.all') }}
        </option>
        <option
          v-for="option in config.options"
          :key="option.value"
          :value="option.value">
          {{ option.label }}
        </option>
      </select>
    </div>

    <!-- Bespoke controls -->
    <slot></slot>

    <!-- Clear + view actions -->
    <div class="ml-auto flex items-end gap-2">
      <slot name="actions"></slot>
      <button
        v-if="showClear"
        type="button"
        :disabled="!hasActiveFilters"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
        @click="emit('clear')">
        <OIcon
          collection="heroicons"
          name="x-mark"
          size="4" />
        {{ t('web.admin.kit.filterBar.clearFilters') }}
      </button>
    </div>
  </div>
</template>
