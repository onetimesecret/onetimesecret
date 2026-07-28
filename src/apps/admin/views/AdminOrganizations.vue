<!-- src/apps/admin/views/AdminOrganizations.vue -->

<script setup lang="ts">
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { DataTable, FilterBar, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useOrganizationsList } from '@/apps/admin/composables/useOrganizationsList';
  import type { ColonelOrganization } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { getPlanLabel } from '@/types/billing';
  import { formatDisplayDateTime, formatRelativeTime } from '@/utils/format';
  import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
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
   * - LIST via {@link useOrganizationsList} (a paginated data source over the
   *   existing `GET /api/colonel/organizations`) + {@link DataTable} +
   *   {@link FilterBar} (subscription + sync-status server filters) +
   *   {@link KitPagination}.
   *
   * COLUMNS. The list leads with the org NAME, then the two addresses an
   * operator actually needs to route a support request — contact and billing —
   * both obscured by default via {@link RevealEmail}. The OWNER address is
   * deliberately absent: it belongs to the detail page. It still travels on the
   * wire because the server's `search` filter matches on it.
   *
   * There is no standalone sync-status column. `sync_status` is `synced` for a
   * healthy fleet and the cell rendered an em dash for every row, which read as
   * "this column is broken". The stale/unknown signal is NOT dropped — it is
   * folded into the plan cell as a badge, so the sync-status filter still has a
   * visible per-row effect (without it, a filtered result set would look
   * identical to an unfiltered one).
   */
  const { t } = useI18n();
  const router = useRouter();

  const { organizations, pagination, cacheMeta, loading, error, perPage, fetchPage } =
    useOrganizationsList();

  // ---- Filters --------------------------------------------------------------

  const SYNC_STATUS_OPTIONS = ['potentially_stale', 'unknown', 'synced'] as const;
  const SUBSCRIPTION_OPTIONS = ['active', 'trialing', 'past_due', 'canceled'] as const;

  // `search` is SERVER-SIDE and was implemented end-to-end all along — the
  // endpoint's #matches_search? does an exact match on objid/extid plus a
  // case-insensitive substring across the contact/owner/billing addresses — but
  // the bar was mounted with `:show-search="false"`, so the only way to find one
  // org was to page through the whole fleet. Same 300 ms debounce + no-op guard
  // wiring as AdminDomains/AdminCustomers.
  const searchTerm = ref('');
  const activeSearch = ref('');
  const statusFilter = ref('');
  const syncStatusFilter = ref('');

  const hasActiveFilters = computed(
    () =>
      searchTerm.value !== '' || statusFilter.value !== '' || syncStatusFilter.value !== ''
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
    { key: 'name', label: t('web.colonel.organizations.columns.name') },
    { key: 'contact_email', label: t('web.colonel.organizations.columns.contactEmail') },
    { key: 'billing_email', label: t('web.colonel.organizations.columns.billingEmail') },
    { key: 'billing', label: t('web.colonel.organizations.columns.planSubscription') },
    { key: 'usage', label: t('web.colonel.organizations.columns.usage') },
    { key: 'created', label: t('web.colonel.organizations.columns.created') },
  ]);

  /**
   * The org's display name, ALWAYS rendered when present — including the
   * `Default Workspace` auto-name, which the previous subtitle suppressed and
   * so left every default org blank. Falls back to the extid only when the name
   * is genuinely missing.
   */
  function orgName(row: ColonelOrganization): string {
    return row.display_name?.trim() ? row.display_name : row.extid;
  }
  function hasOrgName(row: ColonelOrganization): boolean {
    return Boolean(row.display_name?.trim());
  }

  /**
   * `billing_email` is unset on most orgs (billing falls back to the contact
   * address). Distinguish the two cases rather than showing an em dash for a
   * column that is almost never populated: an explicit "same as contact" when
   * the two addresses match, an em dash only when there is genuinely no billing
   * address on record.
   */
  function billingSameAsContact(row: ColonelOrganization): boolean {
    const billing = row.billing_email?.trim().toLowerCase();
    const contact = row.contact_email?.trim().toLowerCase();
    return Boolean(billing && contact && billing === contact);
  }
  function hasBillingEmail(row: ColonelOrganization): boolean {
    return Boolean(row.billing_email?.trim());
  }

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

  // ---- Roster-cache read-out ------------------------------------------------

  /**
   * "Updated <n> ago", sourced from the server's `details.cache.generated_at`
   * (the unix second the ROSTER was built, not when this response was served),
   * so it keeps counting up across cache hits and resets on a refresh.
   */
  const updatedAgo = computed(() => {
    const generatedAt = cacheMeta.value?.generated_at;
    if (!generatedAt) return '';
    return formatRelativeTime(new Date(generatedAt * 1000));
  });

  // ---- List fetching --------------------------------------------------------

  function load(targetPage = 1, options: { refresh?: boolean } = {}): Promise<void> {
    return fetchPage(
      targetPage,
      {
        search: activeSearch.value || undefined,
        status: statusFilter.value || undefined,
        sync_status: syncStatusFilter.value || undefined,
      },
      options
    );
  }

  // Debounce search input so we issue one request per pause, not per keystroke.
  let searchTimer: ReturnType<typeof setTimeout> | null = null;
  watch(searchTerm, (value) => {
    if (searchTimer) clearTimeout(searchTimer);
    // Skip no-op changes (e.g. the programmatic reset in onClear(), which
    // already issues its own fetch) so clearing doesn't double-fetch.
    if (value.trim() === activeSearch.value) return;
    searchTimer = setTimeout(() => {
      activeSearch.value = value.trim();
      load(1);
    }, 300);
  });
  onBeforeUnmount(() => {
    if (searchTimer) clearTimeout(searchTimer);
  });

  /** Header control: bypass the server's roster cache and rebuild it. */
  function onRefresh(): void {
    load(pagination.value?.page ?? 1, { refresh: true });
  }

  function onFilterChange(key: string, value: string): void {
    if (key === 'sync_status') syncStatusFilter.value = value;
    else if (key === 'status') statusFilter.value = value;
    load(1);
  }
  function onClear(): void {
    // Cancel any in-flight debounce so the reset below doesn't fire a second,
    // late request on top of this one.
    if (searchTimer) clearTimeout(searchTimer);
    searchTerm.value = '';
    activeSearch.value = '';
    statusFilter.value = '';
    syncStatusFilter.value = '';
    load(1);
  }
  function onPageChange(targetPage: number): void {
    load(targetPage);
  }
  function onPerPageChange(nextPerPage: number): void {
    perPage.value = nextPerPage;
    load(1);
  }

  // ---- Navigation to the detail page ----------------------------------------

  function openDetail(org: ColonelOrganization): void {
    router.push({ name: 'AdminOrganizationDetail', params: { id: org.extid } });
  }

  onMounted(() => load(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header
      class="mb-6 flex items-start justify-between gap-4 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <div>
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ t('web.colonel.organizations.title') }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.colonel.organizations.description') }}
        </p>
      </div>

      <!-- Roster freshness + explicit cache bypass -->
      <div class="flex shrink-0 flex-col items-end gap-1">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:opacity-50 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-800"
          :disabled="loading"
          data-testid="organizations-refresh"
          @click="onRefresh">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.colonel.organizations.refresh') }}
        </button>
        <span
          v-if="updatedAgo"
          class="text-xs text-gray-500 dark:text-gray-400"
          data-testid="organizations-updated-ago">
          {{ t('web.colonel.organizations.updatedAgo', { ago: updatedAgo }) }}
        </span>
      </div>
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
        @click="load(1)">
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
        v-model:search="searchTerm"
        :filters="filters"
        :search-placeholder="t('web.colonel.organizations.filters.searchPlaceholder')"
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
        <!-- Name (always rendered; extid stays visible as a copyable subtitle) -->
        <template #cell-name="{ row }">
          <div class="font-medium text-gray-900 dark:text-white">
            {{ orgName(row) }}
          </div>
          <div
            v-if="hasOrgName(row)"
            class="font-mono text-xs text-gray-500 dark:text-gray-400">
            {{ row.extid }}
          </div>
        </template>

        <!-- Contact email (obscured by default) -->
        <template #cell-contact_email="{ row }">
          <RevealEmail :email="row.contact_email" />
        </template>

        <!-- Billing email (obscured by default; most orgs inherit the contact) -->
        <template #cell-billing_email="{ row }">
          <span
            v-if="billingSameAsContact(row)"
            class="text-xs text-gray-500 dark:text-gray-400"
            data-testid="billing-email-same-as-contact">
            {{ t('web.colonel.organizations.sameAsContact') }}
          </span>
          <RevealEmail
            v-else-if="hasBillingEmail(row)"
            :email="row.billing_email" />
          <span
            v-else
            class="text-gray-400 dark:text-gray-500"
            >—</span
          >
        </template>

        <!-- Plan & subscription, with the sync-health badge folded in -->
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
          <!-- Sync health: badge problems only (a synced fleet stays quiet). -->
          <template v-if="row.sync_status === 'potentially_stale'">
            <div class="mt-1">
              <span
                class="inline-flex items-center rounded bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-200">
                {{ t('web.colonel.organizations.status.stale') }}
              </span>
            </div>
            <div
              v-if="row.sync_status_reason"
              class="mt-1 max-w-xs text-xs whitespace-normal text-yellow-700 dark:text-yellow-300">
              {{ row.sync_status_reason }}
            </div>
          </template>
          <div
            v-else-if="row.sync_status === 'unknown'"
            class="mt-1">
            <span
              class="inline-flex items-center rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300">
              {{ t('web.colonel.organizations.status.unknown') }}
            </span>
          </div>
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
