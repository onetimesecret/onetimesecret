<!-- src/apps/admin/views/AdminOrganizations.vue -->

<script setup lang="ts">
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { DataTable, FilterBar, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useAdminOrganizations } from '@/apps/admin/stores/useAdminOrganizations';
  import type { ColonelOrganization } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { getPlanLabel } from '@/types/billing';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  /**
   * Organizations screen — billing health monitor (list). A row navigates to the
   * first-class {@link AdminOrganizationDetail} page (route
   * `/colonel/organizations/:id`, keyed by the org's PUBLIC id / extid), which
   * owns the billing read-out, the entitlement breakdown + grant/revoke/clear,
   * the members + domains tables, and the investigate + reconcile remediation.
   *
   * The old in-view drawer (+ investigate / entitlement workflows) was removed:
   * the audit found "the organization has no detail page", so those flows now
   * live on the detail page where the operator can see full state before acting.
   *
   * - LIST via {@link useAdminOrganizations} (a per-resource paginated store over
   *   the existing `GET /api/colonel/organizations`) + {@link DataTable} +
   *   {@link FilterBar} (subscription + sync-status server filters) +
   *   {@link KitPagination}. Leads with the unique identifier (contact_email),
   *   obscured by default via {@link RevealEmail}, and badges only problems
   *   (potentially_stale / unknown).
   */
  const { t } = useI18n();
  const router = useRouter();

  const store = useAdminOrganizations();
  const { organizations, pagination, loading, error } = storeToRefs(store);

  // ---- Filters --------------------------------------------------------------

  const SYNC_STATUS_OPTIONS = ['potentially_stale', 'unknown', 'synced'] as const;
  const SUBSCRIPTION_OPTIONS = ['active', 'trialing', 'past_due', 'canceled'] as const;

  const statusFilter = ref('');
  const syncStatusFilter = ref('');

  const hasActiveFilters = computed(
    () => statusFilter.value !== '' || syncStatusFilter.value !== ''
  );

  const SYNC_FILTER_LABELS: Record<string, string> = {
    potentially_stale: 'web.colonel.organizations.filters.potentiallyStale',
    unknown: 'web.colonel.organizations.filters.unknown',
    synced: 'web.colonel.organizations.filters.synced',
  };
  const SUBSCRIPTION_FILTER_LABELS: Record<string, string> = {
    active: 'web.colonel.organizations.filters.active',
    trialing: 'web.colonel.organizations.filters.trialing',
    past_due: 'web.colonel.organizations.filters.pastDue',
    canceled: 'web.colonel.organizations.filters.canceled',
  };

  const filters = computed<FilterConfig[]>(() => [
    {
      key: 'sync_status',
      label: t('web.colonel.organizations.filters.syncStatus'),
      value: syncStatusFilter.value,
      options: SYNC_STATUS_OPTIONS.map((v) => ({ value: v, label: t(SYNC_FILTER_LABELS[v]) })),
    },
    {
      key: 'status',
      label: t('web.colonel.organizations.filters.subscription'),
      value: statusFilter.value,
      options: SUBSCRIPTION_OPTIONS.map((v) => ({
        value: v,
        label: t(SUBSCRIPTION_FILTER_LABELS[v]),
      })),
    },
  ]);

  // ---- Columns --------------------------------------------------------------

  const columns = computed<DataTableColumn<ColonelOrganization>[]>(() => [
    { key: 'account', label: t('web.colonel.organizations.columns.account') },
    { key: 'billing', label: t('web.colonel.organizations.columns.billing') },
    { key: 'status', label: t('web.colonel.organizations.columns.status') },
    { key: 'usage', label: t('web.colonel.organizations.columns.usage') },
    { key: 'created', label: t('web.colonel.organizations.columns.created') },
  ]);

  function planLabel(planid: string | null): string {
    return planid ? getPlanLabel(planid) : getPlanLabel('free');
  }

  /** Only non-normal subscription states get a coloured badge. */
  function subscriptionBadgeClass(status: string | null): string {
    switch (status) {
      case 'trialing':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900/50 dark:text-blue-200';
      case 'past_due':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-200';
      case 'canceled':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      default:
        return '';
    }
  }
  function needsSubscriptionBadge(status: string | null): boolean {
    return status !== null && status !== 'active';
  }

  const totalOrganizations = computed(() => pagination.value?.total_count ?? 0);
  const staleCount = computed(
    () => organizations.value.filter((o) => o.sync_status === 'potentially_stale').length
  );
  const unknownCount = computed(
    () => organizations.value.filter((o) => o.sync_status === 'unknown').length
  );

  // ---- List fetching --------------------------------------------------------

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage, {
        status: statusFilter.value || undefined,
        sync_status: syncStatusFilter.value || undefined,
      });
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // below handle it. Swallow so it doesn't become an unhandled rejection.
    }
  }

  function onFilterChange(key: string, value: string): void {
    if (key === 'sync_status') syncStatusFilter.value = value;
    else if (key === 'status') statusFilter.value = value;
    fetchPage(1);
  }
  function onClear(): void {
    statusFilter.value = '';
    syncStatusFilter.value = '';
    fetchPage(1);
  }
  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }
  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Navigation to the detail page ----------------------------------------

  function openDetail(org: ColonelOrganization): void {
    router.push({ name: 'AdminOrganizationDetail', params: { id: org.extid } });
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.colonel.organizations.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.colonel.organizations.description') }}
      </p>
    </header>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="organizations-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.organizations.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.organizations.retry') }}
      </button>
    </div>

    <!-- Count summary (stale / unknown highlighted) -->
    <p class="mb-3 text-sm text-gray-600 dark:text-gray-400">
      {{ t('web.colonel.organizations.organizationsCount', { count: totalOrganizations }) }}
      <template v-if="staleCount > 0 || unknownCount > 0">
        <span class="mx-1">-</span>
        <span
          v-if="staleCount > 0"
          class="font-medium text-yellow-600 dark:text-yellow-400">
          {{ t('web.colonel.organizations.needAttention', { count: staleCount }) }}
        </span>
        <span
          v-if="staleCount > 0 && unknownCount > 0"
          class="mx-1"
          >/</span
        >
        <span
          v-if="unknownCount > 0"
          class="text-gray-500 dark:text-gray-400">
          {{ t('web.colonel.organizations.unknownCount', { count: unknownCount }) }}
        </span>
      </template>
    </p>

    <!-- Filters -->
    <div class="mb-4">
      <FilterBar
        :filters="filters"
        :show-search="false"
        :has-active-filters="hasActiveFilters"
        testid="organizations-filterbar"
        @filter-change="onFilterChange"
        @clear="onClear" />
    </div>

    <!-- Table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="organizations"
        row-key="extid"
        :loading="loading"
        :empty-text="t('web.colonel.organizations.noOrganizations')"
        clickable-rows
        testid="organizations-table"
        @row-click="openDetail">
        <!-- Account (email obscured by default; falls back to the extid). -->
        <template #cell-account="{ row }">
          <div class="font-medium text-gray-900 dark:text-white">
            <RevealEmail
              v-if="row.contact_email"
              :email="row.contact_email" />
            <span
              v-else
              class="font-mono text-xs text-gray-500 dark:text-gray-400"
              >{{ row.extid }}</span
            >
          </div>
          <div
            v-if="row.display_name && row.display_name !== 'Default Workspace'"
            class="text-xs text-gray-500 dark:text-gray-400">
            {{ row.display_name }}
          </div>
        </template>

        <!-- Billing (plan + subscription) -->
        <template #cell-billing="{ row }">
          <div class="text-sm text-gray-900 dark:text-white">
            {{ planLabel(row.planid) }}
          </div>
          <div class="mt-0.5">
            <span
              v-if="needsSubscriptionBadge(row.subscription_status)"
              class="inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium"
              :class="subscriptionBadgeClass(row.subscription_status)">
              {{ row.subscription_status }}
            </span>
            <span
              v-else-if="row.subscription_status === 'active'"
              class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.colonel.organizations.status.active') }}
            </span>
            <span
              v-else
              class="text-xs text-gray-400 dark:text-gray-500"
              >—</span
            >
          </div>
        </template>

        <!-- Status (badge problems only) -->
        <template #cell-status="{ row }">
          <template v-if="row.sync_status === 'potentially_stale'">
            <span
              class="inline-flex items-center rounded bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-200">
              {{ t('web.colonel.organizations.status.stale') }}
            </span>
            <div
              v-if="row.sync_status_reason"
              class="mt-1 max-w-xs text-xs whitespace-normal text-yellow-700 dark:text-yellow-300">
              {{ row.sync_status_reason }}
            </div>
          </template>
          <span
            v-else-if="row.sync_status === 'unknown'"
            class="inline-flex items-center rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300">
            {{ t('web.colonel.organizations.status.unknown') }}
          </span>
          <span
            v-else
            class="text-xs text-gray-400 dark:text-gray-500"
            >—</span
          >
        </template>

        <!-- Usage (members / domains) -->
        <template #cell-usage="{ row }">
          <span :title="t('web.colonel.organizations.usage.members', { count: row.member_count })"
            >{{ row.member_count }}m</span
          >
          <span class="mx-1">/</span>
          <span :title="t('web.colonel.organizations.usage.domains', { count: row.domain_count })"
            >{{ row.domain_count }}d</span
          >
        </template>

        <!-- Created -->
        <template #cell-created="{ row }">
          {{ formatDisplayDateTime(row.created) }}
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
