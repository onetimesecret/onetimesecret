// src/apps/admin/components/kit/index.ts

/**
 * Admin UI kit (ticket #11) — the reusable console component set every later
 * admin view composes instead of hand-rolling tables/filters/modals.
 *
 * Import from the barrel so views depend on the kit surface, not file paths:
 *
 *   import { DataTable, StatCard, AdminConfirmDialog } from '@/apps/admin/components/kit';
 *
 * Everything here composes shared leaf primitives (OIcon, EmptyState,
 * TableSkeleton, Skeleton, CopyButton, headlessui) and has ZERO import edge into
 * `src/apps/colonel/*`, keeping the isolated admin bundle free of the retiring
 * legacy tree.
 */

export { default as DataTable } from './DataTable.vue';
export { default as StatCard } from './StatCard.vue';
export { default as FilterBar } from './FilterBar.vue';
export { default as DetailDrawer } from './DetailDrawer.vue';
export { default as JsonViewer } from './JsonViewer.vue';
export { default as AdminConfirmDialog } from './AdminConfirmDialog.vue';
export { default as AdminModal } from './AdminModal.vue';
export { default as AdminRecordPanel } from './AdminRecordPanel.vue';
export { default as KitPagination } from './KitPagination.vue';

export type {
  CellAlign,
  DataTableColumn,
  SortDirection,
  SortState,
  FilterOption,
  FilterConfig,
} from './types';
