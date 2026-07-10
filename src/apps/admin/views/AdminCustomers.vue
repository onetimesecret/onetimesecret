<!-- src/apps/admin/views/AdminCustomers.vue -->

<script setup lang="ts">

  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import {
    DataTable,
    DetailDrawer,
    FilterBar,
    KitPagination,
    StatCard,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useAdminCustomers } from '@/apps/admin/stores/useAdminCustomers';
  import type { ColonelUser } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

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

  // Detail is a slide-over drawer (the console's standard inspect pattern, same
  // as organizations / sessions) rather than a full-page route, so a row click
  // never yanks you out of the list you're scanning. The drawer renders from the
  // row data already in hand — no second fetch — and offers "Open full page" for
  // the deep, mutating actions that live on AdminCustomerDetail.
  const drawerOpen = ref(false);
  const selectedCustomer = ref<ColonelUser | null>(null);

  /** Read-only summary rows for the drawer's field grid. */
  const drawerFields = computed(() => {
    const c = selectedCustomer.value;
    if (!c) return [];
    return [
      {
        key: 'publicId',
        label: t('web.admin.customers.detail.fields.publicId'),
        value: c.user_id,
        mono: true,
      },
      {
        key: 'created',
        label: t('web.admin.customers.detail.fields.created'),
        value: formatDisplayDateTime(c.created),
        mono: false,
      },
      {
        key: 'lastLogin',
        label: t('web.admin.customers.detail.fields.lastLogin'),
        value: c.last_login
          ? formatDisplayDateTime(c.last_login)
          : t('web.admin.customers.detail.never'),
        mono: false,
      },
    ];
  });

  function openDetail(row: ColonelUser): void {
    selectedCustomer.value = row;
    drawerOpen.value = true;
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.customers.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.customers.description') }}
      </p>
    </header>

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
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
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
          <span class="font-medium text-gray-900 dark:text-white">
            <RevealEmail :email="row.email" />
          </span>
          <span
            v-if="row.suspended"
            class="ml-2 inline-flex rounded bg-red-100 px-2 py-0.5 text-xs font-semibold tracking-wide text-red-800 uppercase dark:bg-red-900/40 dark:text-red-200"
            data-testid="suspended-badge">
            {{ t('web.admin.customers.suspended.badge') }}
          </span>
        </template>

        <template #cell-role="{ row }">
          <!-- Elevated roles are flagged as ATTENTION (amber), not danger:
               red is reserved for destructive/suspended states. -->
          <span
            class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-brand text-[11px] font-semibold tracking-wide uppercase"
            :class="
              row.role === 'colonel' || row.role === 'admin'
                ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200'
                : 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300'
            ">
            <OIcon
              v-if="row.role === 'colonel' || row.role === 'admin'"
              collection="heroicons"
              name="shield-check"
              size="3"
              class="shrink-0" />
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
            :aria-label="t('web.admin.customers.detail.no')">—</span>
        </template>

        <template #cell-plan="{ row }">
          {{ row.planid || t('web.admin.customers.detail.none') }}
        </template>

        <template #cell-secrets="{ row }">
          <span class="font-mono tabular-nums">{{ row.secrets_count }}</span>
        </template>

        <template #cell-created="{ row }">
          <span class="text-gray-500 tabular-nums dark:text-gray-400">{{
            formatDisplayDateTime(row.created)
          }}</span>
        </template>

        <template #cell-lastLogin="{ row }">
          <span class="text-gray-500 tabular-nums dark:text-gray-400">{{
            row.last_login ? formatDisplayDateTime(row.last_login) : t('web.admin.customers.detail.never')
          }}</span>
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

    <!-- Detail drawer: read-only summary + escalation to the full page. Mirrors
         the organizations / sessions drawers so every row click behaves alike. -->
    <DetailDrawer
      v-model:open="drawerOpen"
      width-class="max-w-2xl"
      :title="selectedCustomer?.email"
      :subtitle="selectedCustomer?.user_id"
      testid="customers-drawer">
      <div
        v-if="selectedCustomer"
        class="space-y-8">
        <div
          v-if="selectedCustomer.suspended"
          class="rounded-md bg-red-50 px-3 py-2 text-sm font-medium text-red-800 dark:bg-red-900/20 dark:text-red-200"
          data-testid="customer-drawer-suspended">
          {{ t('web.admin.customers.suspended.badge') }}
        </div>

        <section>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard
              :label="t('web.admin.customers.columns.role')"
              :value="t(`web.admin.customers.roles.${selectedCustomer.role}`, selectedCustomer.role)"
              icon="shield-check"
              testid="customer-stat-role" />
            <StatCard
              :label="t('web.admin.customers.columns.verified')"
              :value="
                selectedCustomer.verified
                  ? t('web.admin.customers.detail.yes')
                  : t('web.admin.customers.detail.no')
              "
              icon="check-circle"
              testid="customer-stat-verified" />
            <StatCard
              :label="t('web.admin.customers.columns.plan')"
              :value="selectedCustomer.planid || t('web.admin.customers.detail.none')"
              icon="credit-card" />
            <StatCard
              :label="t('web.admin.customers.columns.secrets')"
              :value="selectedCustomer.secrets_count"
              icon="key"
              testid="customer-stat-secrets" />
          </div>

          <dl class="mt-5 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in drawerFields"
              :key="field.key"
              :data-testid="`customer-field-${field.key}`">
              <dt
                class="font-brand text-[11px] font-semibold tracking-[0.1em] text-gray-500 uppercase dark:text-gray-400">
                {{ field.label }}
              </dt>
              <dd
                v-if="field.mono"
                class="mt-1 inline-block rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs break-all text-gray-700 tabular-nums dark:bg-gray-800 dark:text-gray-300">
                {{ field.value }}
              </dd>
              <dd
                v-else
                class="mt-1 text-sm break-words text-gray-900 tabular-nums dark:text-gray-100">
                {{ field.value }}
              </dd>
            </div>
          </dl>
        </section>

        <!-- Escalation: the deep, mutating actions live on the full page. -->
        <section class="border-t border-gray-200 pt-6 dark:border-gray-800">
          <router-link
            :to="{ name: 'AdminCustomerDetail', params: { id: selectedCustomer.user_id } }"
            class="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
            data-testid="customer-open-full-page">
            {{ t('web.admin.customers.detail.openFullPage') }}
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              size="4" />
          </router-link>
        </section>
      </div>
    </DetailDrawer>
  </div>
</template>
