// src/apps/admin/components/kit/types.ts

/**
 * Shared, frozen type contracts for the admin UI kit (ticket #11).
 *
 * These shapes are the config-driven surface that every later admin view
 * (starting with #22's Customers UI) composes against, so they are treated as
 * a stable API: prefer adding OPTIONAL fields over changing existing ones.
 *
 * The kit lives entirely under `src/apps/admin/` and composes shared leaf
 * primitives (OIcon, EmptyState, TableSkeleton, headlessui) — it has ZERO
 * import edge into `src/apps/colonel/*`, so it never drags the retiring legacy
 * tree into the isolated admin bundle.
 */

/** Horizontal alignment for a {@link DataTableColumn} header + cell. */
export type CellAlign = 'left' | 'center' | 'right';

/**
 * A single column definition for {@link DataTable}. Replaces the hand-rolled,
 * repeated `<th>`/`<td>` class strings in the legacy colonel views with one
 * config object per column.
 */
export interface DataTableColumn<T = Record<string, unknown>> {
  /** Unique column id. Also the default row-value key + the slot suffix. */
  key: string;
  /** Column header text (already translated by the caller). */
  label: string;
  /** When true, the header becomes a sort toggle that emits `update:sort`. */
  sortable?: boolean;
  /** Header + cell alignment. Defaults to `'left'`. */
  align?: CellAlign;
  /** Extra utility classes merged onto this column's `<th>`. */
  headerClass?: string;
  /** Extra utility classes merged onto this column's `<td>`. */
  cellClass?: string;
  /** Optional fixed-width utility class, e.g. `'w-32'`. */
  widthClass?: string;
  /**
   * Value accessor used for the default text cell when no `cell-<key>` slot is
   * supplied. Falls back to `row[key]` when omitted.
   */
  accessor?: (row: T) => unknown;
}

/** Sort direction emitted by {@link DataTable}. */
export type SortDirection = 'asc' | 'desc';

/**
 * Controlled sort state. `DataTable` is sort-agnostic: it renders the indicator
 * from this prop and emits the next state on click, so the owner decides
 * whether to sort the current page client-side or re-fetch server-side
 * (the cursor/server-page model behind `usePaginatedFetch`).
 */
export interface SortState {
  key: string;
  direction: SortDirection;
}

/** A single option in a {@link FilterConfig} native `<select>`. */
export interface FilterOption {
  value: string;
  label: string;
}

/**
 * Config for one filter control rendered by {@link FilterBar}. Renders a native
 * `<select>` (accessibility depends on native semantics — see #11 notes) and is
 * fully controlled: the owner holds the value and updates it from `filter-change`.
 */
export interface FilterConfig {
  /** Unique filter id, echoed back in the `filter-change` event. */
  key: string;
  /** Visible label for the control. */
  label: string;
  /** Selectable options. */
  options: FilterOption[];
  /** Current selected value (controlled). Empty string selects `allLabel`. */
  value?: string;
  /**
   * When set, an empty-value option with this label is prepended (the "no
   * filter" / "All" choice). Defaults to a translated "All".
   */
  allLabel?: string;
}
