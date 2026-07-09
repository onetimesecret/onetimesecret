<!-- src/apps/admin/views/AdminOrganizations.vue -->

<script setup lang="ts">
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import {
    AdminConfirmDialog,
    DataTable,
    DetailDrawer,
    FilterBar,
    JsonViewer,
    KitPagination,
    StatCard,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminOrganizations } from '@/apps/admin/stores/useAdminOrganizations';
  import type {
    ColonelOrganization,
    InvestigateOrganizationResult,
  } from '@/schemas/api/internal/responses/colonel';
  import type { ColonelEntitlementOverrideRecord } from '@/schemas/api/internal/responses/colonel-organizations';
  import { investigateOrganizationResponseSchema } from '@/schemas/api/internal/responses/colonel';
  import { colonelEntitlementOverrideResponseSchema } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { getPlanLabel } from '@/types/billing';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Organizations screen — billing health monitor + billing-investigate workflow
   * + entitlement-override management (ticket #32, Phase-2 parity port; #2349).
   *
   * Rebuilt fresh on the Slice-3 template; it does NOT import the retiring
   * `src/apps/colonel/views/ColonelOrganizations.vue` (806 lines) but preserves
   * its behaviour: lead with the unique identifier (contact_email), badge only
   * problems (potentially_stale / unknown), group billing data, and expose the
   * on-demand billing investigation.
   *
   * - LIST via {@link useAdminOrganizations} (a per-resource paginated store over
   *   the existing `GET /api/colonel/organizations`) + {@link DataTable} +
   *   {@link FilterBar} (subscription + sync-status server filters) +
   *   {@link KitPagination}. One server page per request (CONTRACT 1). Reuses the
   *   existing `colonelOrganizationsResponseSchema` (CONTRACT 3 — no schema drift).
   * - A row opens a {@link DetailDrawer} with the org's billing read-out and the
   *   two per-org workflows:
   *     1. INVESTIGATE — POSTs `organizations/:extid/investigate` (read-only; no
   *        mutation, no audit) and renders the comparison verdict / issues / Stripe
   *        summary as structured markup PLUS the raw payload via {@link JsonViewer}
   *        (the acceptance criterion replacing the legacy ad-hoc markup).
   *     2. ENTITLEMENT OVERRIDES — grant / revoke / clear, each a MUTATING billing
   *        action, so each goes through {@link useAdminMutation} + a
   *        typed-confirmation {@link AdminConfirmDialog} (retype the org's public
   *        id) and is audited server-side (CONTRACT 3 / 4 / D4).
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

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

  /** Lead with the unique identifier, not the generic "Default Workspace". */
  function primaryIdentifier(org: ColonelOrganization): string {
    return org.contact_email || org.extid;
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

  // ---- Detail drawer --------------------------------------------------------

  const drawerOpen = ref(false);
  const selectedOrg = ref<ColonelOrganization | null>(null);

  function openDetail(org: ColonelOrganization): void {
    selectedOrg.value = org;
    // Reset per-org workflow state so a re-opened drawer never shows stale data.
    investigateResult.value = null;
    investigateError.value = null;
    overrideState.value = null;
    entitlementInput.value = '';
    resetEntitlement();
    drawerOpen.value = true;
  }

  const drawerFields = computed(() => {
    const o = selectedOrg.value;
    if (!o) return [];
    return [
      { key: 'contactEmail', label: t('web.admin.organizations.fields.contactEmail'), value: o.contact_email || '—' },
      { key: 'owner', label: t('web.admin.organizations.fields.owner'), value: o.owner_email || '—' },
      { key: 'plan', label: t('web.admin.organizations.fields.plan'), value: planLabel(o.planid) },
      { key: 'subscription', label: t('web.admin.organizations.fields.subscription'), value: o.subscription_status || '—' },
      { key: 'periodEnd', label: t('web.admin.organizations.fields.periodEnd'), value: o.subscription_period_end || '—' },
      { key: 'billingEmail', label: t('web.admin.organizations.fields.billingEmail'), value: o.billing_email || '—' },
      { key: 'stripeCustomer', label: t('web.admin.organizations.fields.stripeCustomer'), value: o.stripe_customer_id || '—', mono: true },
      { key: 'stripeSubscription', label: t('web.admin.organizations.fields.stripeSubscription'), value: o.stripe_subscription_id || '—', mono: true },
      { key: 'orgId', label: t('web.admin.organizations.fields.orgId'), value: o.extid, mono: true },
      { key: 'created', label: t('web.admin.organizations.fields.created'), value: formatDisplayDateTime(o.created) },
      { key: 'updated', label: t('web.admin.organizations.fields.updated'), value: o.updated ? formatDisplayDateTime(o.updated) : '—' },
    ];
  });

  // ---- Investigate (read-only; POST-to-read, no mutation / no audit) --------

  const investigateLoading = ref(false);
  const investigateError = ref<string | null>(null);
  const investigateResult = ref<InvestigateOrganizationResult | null>(null);

  async function runInvestigate(): Promise<void> {
    const org = selectedOrg.value;
    if (!org) return;

    investigateLoading.value = true;
    investigateError.value = null;
    try {
      const response = await $api.post(
        `/api/colonel/organizations/${encodeURIComponent(org.extid)}/investigate`
      );
      const parsed = gracefulParse(
        investigateOrganizationResponseSchema,
        response.data,
        'InvestigateOrganizationResponse'
      );
      if (parsed.ok) {
        investigateResult.value = parsed.data.record;
      } else {
        // Contract drift: report the mismatch honestly rather than a blank panel.
        investigateError.value = t('web.admin.organizations.investigate.parseError');
      }
    } catch {
      investigateError.value = t('web.colonel.organizations.investigation.failed');
    } finally {
      investigateLoading.value = false;
    }
  }

  function verdictBadgeClass(verdict: string): string {
    switch (verdict) {
      case 'synced':
        return 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200';
      case 'mismatch_detected':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300';
    }
  }
  function verdictLabel(verdict: string): string {
    switch (verdict) {
      case 'synced':
        return t('web.colonel.organizations.investigation.verifiedSynced');
      case 'mismatch_detected':
        return t('web.colonel.organizations.investigation.mismatchFound');
      default:
        return t('web.colonel.organizations.investigation.unableToCompare');
    }
  }
  function severityBadgeClass(severity: string): string {
    switch (severity) {
      case 'critical':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      case 'high':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-200';
      case 'medium':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-200';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300';
    }
  }

  // ---- Entitlement overrides (MUTATING — guarded + audited server-side) ------

  type EntitlementAction = 'grant' | 'revoke' | 'clear';

  const entitlementInput = ref('');
  /** Recomputed override state, populated only after a successful action. */
  const overrideState = ref<ColonelEntitlementOverrideRecord | null>(null);

  const entitlementDialogOpen = ref(false);
  const activeEntitlementAction = ref<EntitlementAction | null>(null);
  /** The entitlement name captured when the dialog was requested (grant/revoke). */
  const pendingEntitlement = ref('');

  const {
    loading: entitlementLoading,
    error: entitlementError,
    run: runEntitlement,
    reset: resetEntitlement,
  } = useAdminMutation(async () => {
    const org = selectedOrg.value;
    const action = activeEntitlementAction.value;
    if (!org || !action) throw new Error('No active entitlement action');

    const base = `/api/colonel/organizations/${encodeURIComponent(org.extid)}/entitlements`;
    const response =
      action === 'clear'
        ? await $api.delete(`${base}/overrides`)
        : await $api.post(`${base}/${action}`, { entitlement: pendingEntitlement.value });

    const parsed = gracefulParse(
      colonelEntitlementOverrideResponseSchema,
      response.data,
      'ColonelEntitlementOverrideResponse'
    );
    // A 2xx means the mutation succeeded server-side regardless of ack shape; a
    // mismatch is reported by gracefulParse but does not fail the action.
    overrideState.value = parsed.ok ? parsed.data.record : null;
  });

  function requestGrant(): void {
    if (!entitlementInput.value.trim()) return;
    pendingEntitlement.value = entitlementInput.value.trim();
    activeEntitlementAction.value = 'grant';
    resetEntitlement();
    entitlementDialogOpen.value = true;
  }
  function requestRevoke(): void {
    if (!entitlementInput.value.trim()) return;
    pendingEntitlement.value = entitlementInput.value.trim();
    activeEntitlementAction.value = 'revoke';
    resetEntitlement();
    entitlementDialogOpen.value = true;
  }
  function requestClear(): void {
    pendingEntitlement.value = '';
    activeEntitlementAction.value = 'clear';
    resetEntitlement();
    entitlementDialogOpen.value = true;
  }

  const entitlementDialogConfig = computed(() => {
    const org = selectedOrg.value;
    const name = primaryIdentifier(org ?? ({} as ColonelOrganization));
    const token = org?.extid; // typed-confirmation: retype the org's public id.
    switch (activeEntitlementAction.value) {
      case 'grant':
        return {
          title: t('web.admin.organizations.entitlements.confirm.grantTitle'),
          description: t('web.admin.organizations.entitlements.confirm.grantDescription', {
            entitlement: pendingEntitlement.value,
            org: name,
          }),
          confirmToken: token,
          variant: 'default' as const,
          confirmText: t('web.admin.organizations.entitlements.grant'),
        };
      case 'revoke':
        return {
          title: t('web.admin.organizations.entitlements.confirm.revokeTitle'),
          description: t('web.admin.organizations.entitlements.confirm.revokeDescription', {
            entitlement: pendingEntitlement.value,
            org: name,
          }),
          confirmToken: token,
          variant: 'danger' as const,
          confirmText: t('web.admin.organizations.entitlements.revoke'),
        };
      case 'clear':
        return {
          title: t('web.admin.organizations.entitlements.confirm.clearTitle'),
          description: t('web.admin.organizations.entitlements.confirm.clearDescription', {
            org: name,
          }),
          confirmToken: token,
          variant: 'danger' as const,
          confirmText: t('web.admin.organizations.entitlements.clear'),
        };
      default:
        return {
          title: '',
          description: undefined,
          confirmToken: undefined,
          variant: 'default' as const,
          confirmText: undefined,
        };
    }
  });

  const ENTITLEMENT_SUCCESS_KEYS: Record<EntitlementAction, string> = {
    grant: 'web.admin.organizations.entitlements.success.granted',
    revoke: 'web.admin.organizations.entitlements.success.revoked',
    clear: 'web.admin.organizations.entitlements.success.cleared',
  };

  async function onEntitlementConfirm(): Promise<void> {
    const action = activeEntitlementAction.value;
    if (!action) return;

    const ok = await runEntitlement();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    entitlementDialogOpen.value = false;
    notifications.show(
      t(ENTITLEMENT_SUCCESS_KEYS[action], { entitlement: pendingEntitlement.value }),
      'success'
    );
    if (action === 'clear') entitlementInput.value = '';
    activeEntitlementAction.value = null;
  }

  function onEntitlementCancel(): void {
    entitlementDialogOpen.value = false;
    activeEntitlementAction.value = null;
    resetEntitlement();
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.colonel.organizations.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.colonel.organizations.description') }}
      </p>
    </div>

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
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
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
        <!-- Account -->
        <template #cell-account="{ row }">
          <div class="font-medium text-gray-900 dark:text-white">{{ primaryIdentifier(row) }}</div>
          <div
            v-if="row.display_name && row.display_name !== 'Default Workspace'"
            class="text-xs text-gray-500 dark:text-gray-400">
            {{ row.display_name }}
          </div>
        </template>

        <!-- Billing (plan + subscription) -->
        <template #cell-billing="{ row }">
          <div class="text-sm text-gray-900 dark:text-white">{{ planLabel(row.planid) }}</div>
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
              class="mt-1 max-w-xs whitespace-normal text-xs text-yellow-700 dark:text-yellow-300">
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

    <!-- Detail drawer: billing read-out + investigate + entitlement overrides -->
    <DetailDrawer
      v-model:open="drawerOpen"
      width-class="max-w-2xl"
      :title="selectedOrg ? primaryIdentifier(selectedOrg) : undefined"
      :subtitle="selectedOrg?.extid"
      testid="organizations-drawer">
      <div
        v-if="selectedOrg"
        class="space-y-8">
        <!-- Billing read-out -->
        <section>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard
              :label="t('web.colonel.organizations.columns.members')"
              :value="selectedOrg.member_count"
              icon="users"
              testid="org-stat-members" />
            <StatCard
              :label="t('web.colonel.organizations.columns.domains')"
              :value="selectedOrg.domain_count"
              icon="globe-alt"
              testid="org-stat-domains" />
            <StatCard
              :label="t('web.admin.organizations.fields.plan')"
              :value="planLabel(selectedOrg.planid)"
              icon="credit-card" />
            <StatCard
              :label="t('web.colonel.organizations.columns.status')"
              :value="selectedOrg.sync_status"
              icon="shield-check" />
          </div>

          <dl class="mt-5 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in drawerFields"
              :key="field.key"
              :data-testid="`org-field-${field.key}`">
              <dt class="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ field.label }}
              </dt>
              <dd
                class="mt-0.5 break-words text-sm text-gray-900 dark:text-gray-100"
                :class="field.mono ? 'font-mono text-xs' : ''">
                {{ field.value }}
              </dd>
            </div>
          </dl>
        </section>

        <!-- Investigate -->
        <section
          class="border-t border-gray-200 pt-6 dark:border-gray-800"
          data-testid="org-investigate">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                {{ t('web.colonel.organizations.investigation.result') }}
              </h3>
              <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.admin.organizations.investigate.description') }}
              </p>
            </div>
            <button
              type="button"
              data-testid="org-investigate-button"
              :disabled="investigateLoading"
              class="inline-flex shrink-0 items-center gap-1 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
              @click="runInvestigate">
              <OIcon
                collection="heroicons"
                :name="investigateLoading ? 'arrow-path' : 'magnifying-glass'"
                size="4"
                :class="investigateLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
              {{
                investigateLoading
                  ? t('web.colonel.organizations.actions.checking')
                  : t('web.colonel.organizations.actions.investigate')
              }}
            </button>
          </div>

          <!-- Investigate error -->
          <div
            v-if="investigateError"
            class="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-300"
            role="alert"
            data-testid="org-investigate-error">
            {{ investigateError }}
          </div>

          <!-- Investigate result -->
          <div
            v-else-if="investigateResult"
            class="mt-4 space-y-4"
            data-testid="org-investigate-result">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
                :class="verdictBadgeClass(investigateResult.comparison.verdict)"
                data-testid="org-investigate-verdict">
                {{ verdictLabel(investigateResult.comparison.verdict) }}
              </span>
              <span class="text-xs text-gray-500 dark:text-gray-400">
                {{ investigateResult.investigated_at }}
              </span>
            </div>

            <p
              v-if="investigateResult.comparison.details"
              class="text-sm text-gray-600 dark:text-gray-300">
              {{ investigateResult.comparison.details }}
            </p>

            <!-- Issues (#2349 parity: field + local vs stripe + severity) -->
            <div
              v-if="investigateResult.comparison.issues?.length"
              class="space-y-2">
              <div
                v-for="(issue, idx) in investigateResult.comparison.issues"
                :key="idx"
                class="rounded border border-gray-200 bg-gray-50 p-2 text-xs dark:border-gray-700 dark:bg-gray-800/50">
                <div class="flex items-center gap-2">
                  <span
                    class="inline-flex items-center rounded px-1.5 py-0.5 font-medium"
                    :class="severityBadgeClass(issue.severity)">
                    {{ issue.severity }}
                  </span>
                  <span class="font-medium text-gray-700 dark:text-gray-300">{{ issue.field }}</span>
                </div>
                <div class="mt-1 grid grid-cols-2 gap-4">
                  <div>
                    <span class="text-gray-500 dark:text-gray-400"
                      >{{ t('web.colonel.organizations.investigation.local') }}:</span
                    >
                    <code class="ml-1 text-gray-900 dark:text-white">{{ issue.local }}</code>
                  </div>
                  <div>
                    <span class="text-gray-500 dark:text-gray-400"
                      >{{ t('web.colonel.organizations.investigation.stripe') }}:</span
                    >
                    <code class="ml-1 text-gray-900 dark:text-white">{{ issue.stripe }}</code>
                  </div>
                </div>
              </div>
            </div>

            <!-- Stripe subscription summary (when available) -->
            <div
              v-if="investigateResult.stripe.available && investigateResult.stripe.subscription"
              class="border-t border-gray-200 pt-3 dark:border-gray-700">
              <h4 class="mb-2 text-xs font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.organizations.investigation.stripeDetails') }}
              </h4>
              <div class="grid grid-cols-2 gap-2 text-xs md:grid-cols-4">
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.statusLabel') }}:</span
                  >
                  <span class="ml-1 font-medium text-gray-900 dark:text-white">{{
                    investigateResult.stripe.subscription.status
                  }}</span>
                </div>
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.product') }}:</span
                  >
                  <span class="ml-1 font-medium text-gray-900 dark:text-white">{{
                    investigateResult.stripe.subscription.product_name || 'N/A'
                  }}</span>
                </div>
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.resolvedPlan') }}:</span
                  >
                  <span class="ml-1 font-medium text-gray-900 dark:text-white">{{
                    investigateResult.stripe.subscription.resolved_plan_id || '(none)'
                  }}</span>
                </div>
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.priceId') }}:</span
                  >
                  <code class="ml-1 font-mono text-gray-700 dark:text-gray-300">{{
                    investigateResult.stripe.subscription.price_id || 'N/A'
                  }}</code>
                </div>
              </div>
            </div>
            <p
              v-else-if="investigateResult.stripe.reason"
              class="text-xs text-gray-500 dark:text-gray-400">
              {{ investigateResult.stripe.reason }}
            </p>

            <!-- Raw payload (AC: JsonViewer replaces the legacy ad-hoc markup) -->
            <div>
              <h4 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.admin.organizations.investigate.rawPayload') }}
              </h4>
              <JsonViewer
                :data="investigateResult"
                :expand-depth="1"
                testid="org-investigate-json" />
            </div>
          </div>
        </section>

        <!-- Entitlement overrides -->
        <section
          class="border-t border-gray-200 pt-6 dark:border-gray-800"
          data-testid="org-entitlements">
          <h3 class="text-base font-semibold text-gray-900 dark:text-white">
            {{ t('web.admin.organizations.entitlements.section') }}
          </h3>
          <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.organizations.entitlements.description') }}
          </p>

          <div class="mt-4">
            <label
              for="org-entitlement-input"
              class="block text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.admin.organizations.entitlements.inputLabel') }}
            </label>
            <div class="mt-2 flex flex-wrap gap-2">
              <input
                id="org-entitlement-input"
                v-model="entitlementInput"
                type="text"
                autocomplete="off"
                spellcheck="false"
                data-testid="org-entitlement-input"
                :placeholder="t('web.admin.organizations.entitlements.placeholder')"
                class="min-w-0 flex-1 rounded-md border border-gray-300 px-3 py-2 font-mono text-sm placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
              <button
                type="button"
                data-testid="org-entitlement-grant"
                :disabled="!entitlementInput.trim()"
                class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
                @click="requestGrant">
                {{ t('web.admin.organizations.entitlements.grant') }}
              </button>
              <button
                type="button"
                data-testid="org-entitlement-revoke"
                :disabled="!entitlementInput.trim()"
                class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
                @click="requestRevoke">
                {{ t('web.admin.organizations.entitlements.revoke') }}
              </button>
            </div>
            <button
              type="button"
              data-testid="org-entitlement-clear"
              class="mt-3 inline-flex items-center gap-1 text-sm font-medium text-red-700 hover:text-red-800 focus:outline-none dark:text-red-400 dark:hover:text-red-300"
              @click="requestClear">
              <OIcon
                collection="heroicons"
                name="trash"
                size="4" />
              {{ t('web.admin.organizations.entitlements.clear') }}
            </button>
          </div>

          <!-- Recomputed override state (populated after an action) -->
          <div
            v-if="overrideState"
            class="mt-5 space-y-3"
            data-testid="org-override-state">
            <div>
              <p class="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.admin.organizations.entitlements.effective') }}
              </p>
              <div class="mt-1 flex flex-wrap gap-1">
                <span
                  v-for="ent in overrideState.effective_entitlements"
                  :key="`eff-${ent}`"
                  class="inline-flex items-center rounded bg-green-50 px-2 py-0.5 font-mono text-xs text-green-700 dark:bg-green-900/40 dark:text-green-200">
                  {{ ent }}
                </span>
                <span
                  v-if="overrideState.effective_entitlements.length === 0"
                  class="text-xs text-gray-400 dark:text-gray-500"
                  >—</span
                >
              </div>
            </div>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <p class="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.organizations.entitlements.grants') }}
                </p>
                <div class="mt-1 flex flex-wrap gap-1">
                  <span
                    v-for="ent in overrideState.grants"
                    :key="`grant-${ent}`"
                    class="inline-flex items-center rounded bg-brand-50 px-2 py-0.5 font-mono text-xs text-brand-700 dark:bg-brand-900/30 dark:text-brand-300">
                    {{ ent }}
                  </span>
                  <span
                    v-if="overrideState.grants.length === 0"
                    class="text-xs text-gray-400 dark:text-gray-500"
                    >—</span
                  >
                </div>
              </div>
              <div>
                <p class="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.organizations.entitlements.revokes') }}
                </p>
                <div class="mt-1 flex flex-wrap gap-1">
                  <span
                    v-for="ent in overrideState.revokes"
                    :key="`revoke-${ent}`"
                    class="inline-flex items-center rounded bg-red-50 px-2 py-0.5 font-mono text-xs text-red-700 dark:bg-red-900/30 dark:text-red-300">
                    {{ ent }}
                  </span>
                  <span
                    v-if="overrideState.revokes.length === 0"
                    class="text-xs text-gray-400 dark:text-gray-500"
                    >—</span
                  >
                </div>
              </div>
            </div>
          </div>
          <p
            v-else
            class="mt-4 text-xs text-gray-400 dark:text-gray-500"
            data-testid="org-override-empty">
            {{ t('web.admin.organizations.entitlements.noOverrides') }}
          </p>
        </section>
      </div>
    </DetailDrawer>

    <!-- Guarded entitlement mutation (typed-confirmation — sibling of the drawer). -->
    <AdminConfirmDialog
      v-model:open="entitlementDialogOpen"
      :title="entitlementDialogConfig.title"
      :description="entitlementDialogConfig.description"
      :confirm-token="entitlementDialogConfig.confirmToken"
      :variant="entitlementDialogConfig.variant"
      :confirm-text="entitlementDialogConfig.confirmText"
      :loading="entitlementLoading"
      :error="entitlementError"
      @confirm="onEntitlementConfirm"
      @cancel="onEntitlementCancel" />
  </div>
</template>
