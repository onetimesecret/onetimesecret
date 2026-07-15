# Admin UI kit

The reusable console component set for the rebuilt Colonel admin (epic: Colonel
Admin Rebuild, ticket #11). Every later admin view composes these instead of
hand-rolling tables/filters/modals, so markup is written once and the API is
stable across phases (this is the foundation for #22's Customers UI).

Import from the barrel:

```ts
import {
  DataTable,
  StatCard,
  FilterBar,
  DetailDrawer,
  JsonViewer,
  AdminConfirmDialog,
  KitPagination,
} from '@/apps/admin/components/kit';
import type { DataTableColumn, SortState, FilterConfig } from '@/apps/admin/components/kit';
```

## Design rules

- **Composition over reinvention.** Everything is built on shared leaf primitives
  (`OIcon`, `EmptyState`, `TableSkeleton`, `Skeleton`, `CopyButton`) and headlessui
  `Dialog`/`Transition`. No bespoke modal / skeleton / icon.
- **Isolation.** Zero import edge into `src/apps/colonel/*` or `colonelInfoStore`
  (enforced by `kit-isolation.spec.ts`), so the admin bundle never drags in the
  retiring legacy tree. The pagination control is re-homed here for this reason.
- **Controlled, not clever.** DataTable sort, FilterBar values and pagination are
  all controlled — the owner (a per-resource store view) holds the state and the
  kit emits the next state. This maps cleanly onto the one-server-page
  `usePaginatedFetch` model (cursor-ready, no load-all-then-slice).
- **Dark + i18n from day one.** All components ship `dark:` variants; user-facing
  strings route through i18n. New strings live under `web.admin.kit.*`; existing
  `web.COMMON.*` / `web.LABELS.*` / `web.colonel.pagination.*` are reused.

## Components

### `DataTable`
Config-driven, sortable table. Replaces per-view `<th>`/`<td>` duplication.

- Props: `columns: DataTableColumn<T>[]`, `rows: T[]`, `rowKey`, `loading?`,
  `sort?: SortState | null`, `emptyText?`, `clickableRows?`, `testid?`.
- Emits: `update:sort` (controlled sort), `row-click` (when `clickableRows`).
- Slots: `cell-<key>` / `header-<key>` per column, plus `empty` / `loading`.

```vue
<DataTable
  :columns="[
    { key: 'email', label: t('...'), sortable: true },
    { key: 'secrets', label: t('...'), align: 'right', accessor: (r) => r.secrets_count },
  ]"
  :rows="store.customers"
  row-key="user_id"
  :loading="store.loading"
  :sort="sort"
  @update:sort="onSort">
  <template #cell-email="{ row }"><a :href="...">{{ row.email }}</a></template>
</DataTable>
```

### `KitPagination`
Re-homed `ColonelPagination` — same frozen emit contract
(`update:page` / `update:perPage` over `page` / `per_page` / `total_count` /
`total_pages`). Its `pagination` prop is exactly the `PageMeta` the shared
`usePaginatedFetch` composable produces, so store → control needs no re-mapping.

### `StatCard`
Dashboard metric tile. Props: `label`, `value?`, `icon?`, `iconCollection?`,
`trend?`, `trendDirection?`, `loading?`, `to?`. Slots: default (custom value),
`icon`, `footer`. Renders as a `<router-link>` when `to` is set.

### `FilterBar`
Config-driven filter toolbar, replacing inline per-view `<select>`s. Renders a
native `<select>` per `FilterConfig` (native semantics for a11y) plus an optional
search box. Controlled: emits `filter-change (key, value)`, `update:search`,
`clear`. Bespoke controls go in the default slot; view actions in `#actions`.

### `DetailDrawer`
Right-hand slide-over for record detail. Props: `open` (`v-model:open`), `title?`,
`subtitle?`, `widthClass?`. Emits `update:open` + `close`. Slots: default (body),
`header`, `footer`. Escape / backdrop / close-button all dismiss.

### `JsonViewer`
Pretty, collapsible, syntax-coloured JSON inspector for raw record inspection.
Props: `data`, `expandDepth?` (default 1), `showToolbar?`. Toolbar offers
expand-all / collapse-all / copy. Read-only — callers must strip secrets/tokens
before passing sensitive records (redaction is governed by the audit log,
CONTRACT 6).

### `AdminConfirmDialog`
The D4 destructive-action gate (frozen API — reused by #22/30/40/41/42/43/44).
Generalises `PasswordConfirmModal` into a **typed-confirmation** dialog.

- Props (frozen): `open`, `title`, `description`, `confirmToken`, `variant`,
  `loading`, `error` (+ optional `confirmText` / `cancelText` / `initialFocus`).
- When `confirmToken` is a non-empty string, the confirm button stays **disabled
  until the typed input EXACTLY equals the token** (case-sensitive, no trim). When
  omitted/empty it degrades to a simple one-click confirm for low-risk actions.
- Emits: `update:open`, `confirm`, `cancel`. Slots: `icon`, `description`, `prompt`.

```vue
<AdminConfirmDialog
  v-model:open="open"
  :title="t('...')"
  :description="t('...')"
  :confirm-token="customer.email"
  variant="danger"
  :loading="deleting"
  :error="error"
  @confirm="onDelete" />
```
