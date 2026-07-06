<!-- src/apps/admin/components/kit/DataTable.vue -->

<script setup lang="ts" generic="T">
  import { useI18n } from 'vue-i18n';

  import OIcon from '@/shared/components/icons/OIcon.vue';
  import EmptyState from '@/shared/components/ui/EmptyState.vue';
  import TableSkeleton from '@/shared/components/closet/TableSkeleton.vue';

  import type { CellAlign, DataTableColumn, SortState } from './types';

  /**
   * Config-driven, sortable table for the admin console (ticket #11).
   *
   * Replaces the per-view `<th>`/`<td>` class-string duplication in the legacy
   * colonel views (e.g. ColonelUsers.vue repeated the same header class 7×) with
   * a single `columns` config. Composes shared primitives only — TableSkeleton
   * for loading, EmptyState for the empty case, OIcon for the sort indicator —
   * so it stays inside the isolated admin bundle.
   *
   * Sorting is CONTROLLED: the indicator renders from the `sort` prop and each
   * click emits the next `SortState`. The owner decides whether to sort the
   * current page in memory or re-fetch a sorted server page — which keeps this
   * aligned with the one-server-page `usePaginatedFetch` model.
   *
   * Per-cell rendering is opt-in via a `cell-<column.key>` slot; without one the
   * column's `accessor` (or `row[key]`) is rendered as plain text. Column headers
   * can likewise be overridden with a `header-<column.key>` slot.
   */
  const props = withDefaults(
    defineProps<{
      /** Column configuration (drives both header and body). */
      columns: DataTableColumn<T>[];
      /** Rows for the CURRENT page (the composable never accumulates pages). */
      rows: T[];
      /**
       * Row identity: a property key on the row, or an accessor returning a
       * stable id. Used for the `v-for` key and echoed by `row-click`.
       */
      rowKey: keyof T | ((row: T) => string | number);
      /** True while a page is loading — shows the TableSkeleton. */
      loading?: boolean;
      /** Controlled sort state, or null for unsorted. */
      sort?: SortState | null;
      /** Overrides the default empty-state title. */
      emptyText?: string;
      /** When true, rows get hover styling + a pointer and emit `row-click`. */
      clickableRows?: boolean;
      /** Accessible caption / test id for the table element. */
      testid?: string;
    }>(),
    {
      loading: false,
      sort: null,
      emptyText: undefined,
      clickableRows: false,
      testid: undefined,
    }
  );

  const emit = defineEmits<{
    /** Next controlled sort state after a sortable header is toggled. */
    'update:sort': [value: SortState];
    /** Emitted when `clickableRows` and a body row is activated. */
    'row-click': [row: T];
  }>();

  const { t } = useI18n();

  const alignClass: Record<CellAlign, string> = {
    left: 'text-left',
    center: 'text-center',
    right: 'text-right',
  };

  function columnAlign(column: DataTableColumn<T>): string {
    return alignClass[column.align ?? 'left'];
  }

  function rowIdentity(row: T): string | number {
    if (typeof props.rowKey === 'function') {
      return props.rowKey(row);
    }
    return row[props.rowKey] as unknown as string | number;
  }

  function cellValue(row: T, column: DataTableColumn<T>): unknown {
    if (column.accessor) {
      return column.accessor(row);
    }
    return (row as Record<string, unknown>)[column.key];
  }

  /** ARIA sort state for a header cell (`ascending` | `descending` | `none`). */
  function ariaSort(column: DataTableColumn<T>): 'ascending' | 'descending' | 'none' | undefined {
    if (!column.sortable) return undefined;
    if (props.sort?.key !== column.key) return 'none';
    return props.sort.direction === 'asc' ? 'ascending' : 'descending';
  }

  function sortIcon(column: DataTableColumn<T>): string {
    if (props.sort?.key !== column.key) return 'chevron-up-down';
    return props.sort.direction === 'asc' ? 'chevron-up' : 'chevron-down';
  }

  function toggleSort(column: DataTableColumn<T>): void {
    if (!column.sortable || props.loading) return;
    const isActive = props.sort?.key === column.key;
    const nextDirection =
      isActive && props.sort?.direction === 'asc' ? 'desc' : 'asc';
    emit('update:sort', { key: column.key, direction: nextDirection });
  }

  function handleRowClick(row: T): void {
    if (props.clickableRows) {
      emit('row-click', row);
    }
  }
</script>

<template>
  <div class="overflow-x-auto">
    <!-- Loading: reuse the shared skeleton rather than a bespoke spinner. -->
    <slot
      v-if="loading"
      name="loading">
      <TableSkeleton />
    </slot>

    <!-- Empty: reuse the shared EmptyState (action suppressed for read views). -->
    <slot
      v-else-if="rows.length === 0"
      name="empty">
      <EmptyState
        :show-action="false"
        :testid="testid ? `${testid}-empty` : undefined">
        <template #title>{{ emptyText ?? t('web.admin.kit.dataTable.empty') }}</template>
        <template #description><span></span></template>
      </EmptyState>
    </slot>

    <table
      v-else
      :data-testid="testid"
      class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
      <thead class="bg-gray-50 dark:bg-gray-800">
        <tr>
          <th
            v-for="column in columns"
            :key="column.key"
            scope="col"
            :aria-sort="ariaSort(column)"
            :class="[
              'px-6 py-3 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400',
              columnAlign(column),
              column.widthClass,
              column.headerClass,
            ]">
            <slot
              :name="`header-${column.key}`"
              :column="column">
              <button
                v-if="column.sortable"
                type="button"
                :disabled="loading"
                :aria-label="t('web.admin.kit.dataTable.sortBy', { column: column.label })"
                class="group inline-flex items-center gap-1 uppercase tracking-wider hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 disabled:cursor-not-allowed dark:hover:text-gray-200"
                @click="toggleSort(column)">
                <span>{{ column.label }}</span>
                <OIcon
                  collection="heroicons"
                  :name="sortIcon(column)"
                  size="4"
                  :class="
                    sort?.key === column.key
                      ? 'text-brand-600 dark:text-brand-400'
                      : 'text-gray-400 dark:text-gray-500'
                  " />
              </button>
              <span v-else>{{ column.label }}</span>
            </slot>
          </th>
        </tr>
      </thead>

      <tbody
        class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
        <tr
          v-for="row in rows"
          :key="rowIdentity(row)"
          :class="
            clickableRows
              ? 'cursor-pointer transition-colors hover:bg-gray-50 dark:hover:bg-gray-800'
              : ''
          "
          @click="handleRowClick(row)">
          <td
            v-for="column in columns"
            :key="column.key"
            :class="[
              'whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-gray-100',
              columnAlign(column),
              column.cellClass,
            ]">
            <slot
              :name="`cell-${column.key}`"
              :row="row"
              :value="cellValue(row, column)"
              :column="column">
              {{ cellValue(row, column) }}
            </slot>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
