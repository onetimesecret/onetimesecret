<!-- src/apps/admin/views/AdminCustomers.vue -->

<script setup lang="ts">
  import { storeToRefs } from 'pinia';
  import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  import { DataTable, FilterBar, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useAdminCustomers } from '@/apps/admin/stores/useAdminCustomers';
  import type { ColonelUser } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';

  /**
   * Customers list — the filterable, index-backed table that replaces the
   * hand-rolled `ColonelUsers.vue` (ticket #22, the Phase-1 reference slice).
   *
   * Pure consumer of the Slice-1 kit + `useAdminCustomers` store (CONTRACT 1):
   * DataTable + FilterBar + KitPagination over `usePaginatedFetch`. One server
   * page per request — never load-all-then-slice. Two server-side filters:
   * `role` and a debounced `search` (the list endpoint resolves it via a
   * bounded scan of the email index PLUS exact extid/objid lookups — wired
   * exactly like the sessions screen's search, so a support agent can paste an
   * address or an id). Columns are non-sortable on purpose: the endpoint returns a
   * FIXED most-recently-modified ordering (epic #20 CONTRACT 6), so there is no
   * server `sort` param to drive a controlled re-fetch.
   */
  const { t } = useI18n();
  const router = useRouter();

  const store = useAdminCustomers();
  const { customers, pagination, loading, error } = storeToRefs(store);

  /** Assignable roles, mirrored from the backend SetRole::VALID_ROLES. */
  const ROLE_OPTIONS = ['colonel', 'admin', 'staff', 'customer'] as const;

  const roleFilter = ref('');
  const searchTerm = ref('');
  const activeSearch = ref('');

  const hasActiveFilters = computed(() => roleFilter.value !== '' || searchTerm.value !== '');

  const filters = computed<FilterConfig[]>(() => [
    {
      key: 'role',
      label: t('web.admin.customers.list.roleFilter'),
      value: roleFilter.value,
      options: ROLE_OPTIONS.map((role) => ({
        value: role,
        label: t(`web.admin.customers.roles.${role}`),
      })),
    },
  ]);

  const columns = computed<DataTableColumn<ColonelUser>[]>(() => [
    { key: 'email', label: t('web.admin.customers.columns.email') },
    { key: 'role', label: t('web.admin.customers.columns.role') },
    { key: 'verified', label: t('web.admin.customers.columns.verified'), align: 'center' },
    { key: 'plan', label: t('web.admin.customers.columns.plan') },
    { key: 'secrets', label: t('web.admin.customers.columns.secrets'), align: 'right' },
    { key: 'created', label: t('web.admin.customers.columns.created') },
    { key: 'lastLogin', label: t('web.admin.customers.columns.lastLogin') },
  ]);

  /** Fetch one server page with the active filters. Errors surface via the store. */
  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(
        targetPage,
        roleFilter.value || undefined,
        activeSearch.value || undefined
      );
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow here so it doesn't become unhandled.
    }
  }

  // Debounce search input so we issue one request per pause, not per keystroke
  // (same 300 ms wiring as AdminSessions).
  let searchTimer: ReturnType<typeof setTimeout> | null = null;
  watch(searchTerm, (value) => {
    if (searchTimer) clearTimeout(searchTimer);
    // Skip no-op changes (e.g. the programmatic reset in onClear(), which
    // already issues its own fetch) so clearing doesn't double-fetch.
    if (value.trim() === activeSearch.value) return;
    searchTimer = setTimeout(() => {
      activeSearch.value = value.trim();
      fetchPage(1);
    }, 300);
  });
  onBeforeUnmount(() => {
    if (searchTimer) clearTimeout(searchTimer);
  });

  function onFilterChange(key: string, value: string): void {
    if (key === 'role') {
      roleFilter.value = value;
      fetchPage(1);
    }
  }

  function onClear(): void {
    // Cancel any in-flight debounce so the reset below doesn't fire a second,
    // late request on top of this one.
    if (searchTimer) clearTimeout(searchTimer);
    roleFilter.value = '';
    searchTerm.value = '';
    activeSearch.value = '';
    fetchPage(1);
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    // The composable owns perPage (reconciled from the server echo); set it then
    // re-fetch the first page at the new size.
    store.perPage = perPage;
    fetchPage(1);
  }

  function openDetail(row: ColonelUser): void {
    // Route by the customer's PUBLIC id (extid). The list exposes it as both
    // `user_id` and `extid`; they are identical.
    router.push({ name: 'AdminCustomerDetail', params: { id: row.user_id } });
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.customers.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.customers.description') }}
      </p>
    </div>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="customers-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.customers.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.customers.detail.retry') }}
      </button>
    </div>

    <!-- Filters -->
    <div class="mb-4">
      <FilterBar
        v-model:search="searchTerm"
        :filters="filters"
        :search-placeholder="t('web.admin.customers.list.searchPlaceholder')"
        :has-active-filters="hasActiveFilters"
        testid="customers-filterbar"
        @filter-change="onFilterChange"
        @clear="onClear" />
    </div>

    <!-- Table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="customers"
        row-key="user_id"
        :loading="loading"
        :empty-text="
          activeSearch
            ? t('web.admin.customers.list.emptySearch')
            : t('web.admin.customers.list.empty')
        "
        clickable-rows
        testid="customers-table"
        @row-click="openDetail">
        <template #cell-email="{ row }">
          <span class="font-medium text-gray-900 dark:text-white">{{ row.email }}</span>
          <span
            v-if="row.suspended"
            class="ml-2 inline-flex rounded bg-red-100 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-red-800 dark:bg-red-900/40 dark:text-red-200"
            data-testid="suspended-badge">
            {{ t('web.admin.customers.suspended.badge') }}
          </span>
        </template>

        <template #cell-role="{ row }">
          <span
            class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
            :class="
              row.role === 'colonel' || row.role === 'admin'
                ? 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200'
                : 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300'
            ">
            {{ t(`web.admin.customers.roles.${row.role}`, row.role) }}
          </span>
        </template>

        <template #cell-verified="{ row }">
          <OIcon
            v-if="row.verified"
            collection="heroicons"
            name="check-circle"
            size="5"
            class="inline text-green-600 dark:text-green-400"
            :aria-label="t('web.admin.customers.detail.yes')" />
          <span
            v-else
            class="text-gray-400 dark:text-gray-600"
            :aria-label="t('web.admin.customers.detail.no')"
            >—</span
          >
        </template>

        <template #cell-plan="{ row }">
          {{ row.planid || t('web.admin.customers.detail.none') }}
        </template>

        <template #cell-secrets="{ row }">
          {{ row.secrets_count }}
        </template>

        <template #cell-created="{ row }">
          {{ formatDisplayDateTime(row.created) }}
        </template>

        <template #cell-lastLogin="{ row }">
          {{ row.last_login ? formatDisplayDateTime(row.last_login) : t('web.admin.customers.detail.never') }}
        </template>
      </DataTable>
    </div>

    <!-- Pagination -->
    <KitPagination
      v-if="pagination"
      :pagination="pagination"
      :loading="loading"
      class="mt-4"
      @update:page="onPageChange"
      @update:per-page="onPerPageChange" />
  </div>
</template>
