---
labels: admin-v2, phase-0, frontend
depends: 10-second-entry-shell
epic: "#3653"
---

# Admin rebuild: admin UI kit (DataTable, StatCard, FilterBar, DetailDrawer, ConfirmDialog, JsonViewer)

## Context
Part of the Colonel Admin Rebuild epic. Phase-0: build the reusable console component kit once so every later admin view composes it instead of hand-rolling tables. Today's colonel views repeat identical markup (e.g. `ColonelUsers.vue:43-70` repeats the same `<th>` class string 7×; `ColonelOrganizations.vue` is 806 lines with inline filter `<select>`s at `:281-323`).

## Scope
Build in `src/apps/admin/` (or a shared admin components dir), composed **on top of existing primitives** — do not reinvent:
- **DataTable** — sortable, paginated, column API (config-driven columns replacing hand-rolled `<th>`/`<td>` blocks).
- **StatCard** — dashboard metric tile.
- **FilterBar** — replaces inline per-view filter `<select>`s.
- **DetailDrawer** — slide-over for record detail.
- **ConfirmDialog** — typed confirmation for destructive ops (built on existing modals).
- **JsonViewer** — pretty/collapsible JSON for raw record inspection.
- Every component ships with full `dark:` variants + i18n from day one.

## Grounding — files & pointers
- Reuse (build ON these): `src/shared/components/ui/{EmptyState,ErrorDisplay,DetailField,CopyButton,SplitButton,ButtonGroup}.vue`, `src/shared/components/modals/{ConfirmDialog,PasswordConfirmModal,SimpleModal}.vue`, `src/shared/components/closet/{TableSkeleton,ListSkeleton,CardGridSkeleton}.vue`, `src/shared/components/icons/OIcon.vue`, notifications in `src/shared/components/ui/notifications/`.
- Mine the workspace app for proven table/settings patterns: `src/apps/workspace/components/domains/DomainsTable.vue`, `src/apps/workspace/components/members/MembersTable.vue`, `src/apps/workspace/components/settings/{SettingsSection,SettingsPageHeader,SettingsNavigation}.vue`.
- Anti-patterns to replace: `src/apps/colonel/ColonelUsers.vue:43-70` (7× repeated `<th>` class strings), `src/apps/colonel/ColonelSecrets.vue:44-104` (duplicated table structure), `src/apps/colonel/ColonelOrganizations.vue:281-323` (inline filter selects), `:347` (table).
- Existing thin wrappers that stay: `src/apps/colonel/components/ColonelListPage.vue` (page chrome), `ColonelPagination.vue`.

## Acceptance criteria
- [ ] DataTable renders from a column config (no per-view `<th>` string duplication) with sort + pagination hooks.
- [ ] StatCard, FilterBar, DetailDrawer, ConfirmDialog, JsonViewer implemented and documented.
- [ ] ConfirmDialog requires typed confirmation for destructive actions; wraps existing `src/shared/components/modals/ConfirmDialog.vue`.
- [ ] Every component built atop the listed shared primitives + `OIcon` (no reinvented modal/skeleton/icon).
- [ ] Every component has `dark:` styling and all user-facing strings routed through i18n.
- [ ] Kit consumable from `src/apps/admin/` shell (from #10).

## Notes / risks
- Reuse discipline: normalize onto existing shared shapes rather than adding new one-off props.
- Keep native `<select>`/`<table>` semantics where accessibility depends on them.
- This is the foundation for #22's Customers UI — API stability matters.
