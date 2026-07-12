<!-- src/apps/admin/views/AdminBilling.vue -->

<script setup lang="ts">

  import { DataTable, DetailDrawer, JsonViewer, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type {
    ColonelBillingPlan,
    ColonelBillingDriftChange,
  } from '@/schemas/api/internal/responses/colonel-billing';
  import { colonelBillingCatalogResponseSchema } from '@/schemas/api/internal/responses/colonel-billing';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Billing catalog drift view (ticket #45, Phase 3) — the LAST Phase-3 item and
   * deliberately READ-ONLY to start. Built fresh on the Slice-3 template; it does
   * NOT import `src/apps/colonel/*` or `colonelInfoStore`.
   *
   * A single schema-aware GET via {@link useResourceFetch} (CONTRACT 1 — single
   * read screens use useResourceFetch, not a paginated store) over the new
   * read-only colonel endpoint:
   *
   *   GET /api/colonel/billing/catalog → GetBillingCatalog
   *
   * The endpoint returns BOTH the configured catalog (billing.yaml) and the live
   * plans (Stripe-synced cache) plus a computed drift summary, so the operator
   * can see "config says X, live says Y" at a glance — that is the whole value.
   *
   * Read-only: nothing here mutates, so nothing is audited (CONTRACT 4). Catalog
   * sync stays CLI-only until this view is trusted (spec).
   */
  const { t } = useI18n();

  const { data, loading, error, validationError, load } = useResourceFetch({
    url: '/api/colonel/billing/catalog',
    schema: colonelBillingCatalogResponseSchema,
    context: 'ColonelBillingCatalogResponse',
  });

  const details = computed(() => data.value?.details ?? null);
  const failed = computed(() => error.value !== null || validationError.value !== null);

  const isLocalConfig = computed(() => details.value?.source === 'local_config');
  const drift = computed(() => details.value?.drift ?? null);

  // Index both sides by planid so a per-plan row can pull either version.
  const configById = computed(() => indexByPlanid(details.value?.config_plans ?? []));
  const liveById = computed(() => indexByPlanid(details.value?.live_plans ?? []));

  function indexByPlanid(plans: ColonelBillingPlan[]): Record<string, ColonelBillingPlan> {
    return plans.reduce<Record<string, ColonelBillingPlan>>((acc, plan) => {
      acc[plan.planid] = plan;
      return acc;
    }, {});
  }

  const changedById = computed<Record<string, ColonelBillingDriftChange>>(() =>
    (drift.value?.changed ?? []).reduce<Record<string, ColonelBillingDriftChange>>((acc, c) => {
      acc[c.planid] = c;
      return acc;
    }, {})
  );

  /** The kind of drift a plan row has, driving its status badge. */
  type PlanStatus = 'in_sync' | 'only_config' | 'only_live' | 'changed';

  interface PlanRow {
    planid: string;
    name: string;
    tier: string;
    status: PlanStatus;
    fields: string[];
  }

  /** Union of both sides, keyed by planid, sorted for a stable table. */
  const planRows = computed<PlanRow[]>(() => {
    if (!details.value) return [];
    const ids = new Set<string>([
      ...details.value.config_plans.map((p) => p.planid),
      ...details.value.live_plans.map((p) => p.planid),
    ]);

    return [...ids].sort().map((planid) => {
      const cfg = configById.value[planid];
      const live = liveById.value[planid];
      const changed = changedById.value[planid];

      let status: PlanStatus;
      if (cfg && !live) status = 'only_config';
      else if (!cfg && live) status = 'only_live';
      else if (changed) status = 'changed';
      else status = 'in_sync';

      const source = cfg ?? live;
      return {
        planid,
        name: source?.name ?? '—',
        tier: source?.tier ?? '—',
        status,
        fields: changed?.fields ?? [],
      };
    });
  });

  const columns = computed<DataTableColumn<PlanRow>[]>(() => [
    { key: 'planid', label: t('web.admin.billing.columns.planid') },
    { key: 'name', label: t('web.admin.billing.columns.name') },
    { key: 'tier', label: t('web.admin.billing.columns.tier') },
    { key: 'status', label: t('web.admin.billing.columns.status') },
    { key: 'actions', label: '', align: 'right' },
  ]);

  function statusBadgeClass(status: PlanStatus): string {
    switch (status) {
      case 'in_sync':
        return 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
      case 'changed':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-200';
      case 'only_config':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-200';
      case 'only_live':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-200';
      default:
        return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
    }
  }

  // ---- Side-by-side diff drawer --------------------------------------------

  const selectedPlanid = ref<string | null>(null);
  const drawerOpen = ref(false);

  const selectedConfig = computed(() =>
    selectedPlanid.value ? (configById.value[selectedPlanid.value] ?? null) : null
  );
  const selectedLive = computed(() =>
    selectedPlanid.value ? (liveById.value[selectedPlanid.value] ?? null) : null
  );

  function openDiff(planid: string): void {
    selectedPlanid.value = planid;
    drawerOpen.value = true;
  }

  onMounted(() => {
    load().catch(() => {});
  });
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.billing.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.billing.description') }}
      </p>
    </header>

    <!-- Loading -->
    <div
      v-if="loading && !details"
      class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
      data-testid="billing-loading">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        size="5"
        class="animate-spin motion-reduce:animate-none" />
      {{ t('web.COMMON.loading') }}
    </div>

    <!-- Error -->
    <div
      v-else-if="failed"
      class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="billing-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.billing.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="load().catch(() => {})">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.billing.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-else-if="details"
      class="space-y-6">
      <!-- local_config warning: drift cannot be evaluated without Stripe. -->
      <div
        v-if="isLocalConfig"
        class="flex items-start gap-2 rounded-md border border-yellow-200 bg-yellow-50 px-4 py-3 dark:border-yellow-900/50 dark:bg-yellow-900/20"
        role="status"
        data-testid="billing-local-config-warning">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="5"
          class="mt-0.5 shrink-0 text-yellow-600 dark:text-yellow-400" />
        <span class="text-sm text-yellow-800 dark:text-yellow-200">
          {{ t('web.admin.billing.localConfigWarning') }}
        </span>
      </div>

      <!-- Summary tiles -->
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard
          :label="t('web.admin.billing.stats.configured')"
          :value="details.config_plans.length"
          icon="document-text"
          testid="stat-configured" />
        <StatCard
          :label="t('web.admin.billing.stats.live')"
          :value="details.live_plans.length"
          icon="rectangle-stack"
          testid="stat-live" />
        <StatCard
          :label="t('web.admin.billing.stats.source')"
          :value="isLocalConfig
            ? t('web.admin.billing.source.localConfig')
            : t('web.admin.billing.source.stripe')"
          icon="signal"
          testid="stat-source" />
        <StatCard
          :label="t('web.admin.billing.stats.drift')"
          :value="drift?.in_sync
            ? t('web.admin.billing.inSync')
            : t('web.admin.billing.driftCount', {
              count: (drift?.only_in_config.length ?? 0)
                + (drift?.only_in_live.length ?? 0)
                + (drift?.changed.length ?? 0),
            })"
          icon="rectangle-group"
          testid="stat-drift" />
      </div>

      <!-- Drift banner: in-sync vs differences present -->
      <div
        v-if="drift?.in_sync"
        class="flex items-center gap-2 rounded-md border border-green-200 bg-green-50 px-4 py-3 dark:border-green-900/50 dark:bg-green-900/20"
        data-testid="billing-in-sync">
        <OIcon
          collection="heroicons"
          name="check-circle"
          size="5"
          class="text-green-600 dark:text-green-400" />
        <span class="text-sm text-green-800 dark:text-green-200">
          {{ t('web.admin.billing.inSyncDetail') }}
        </span>
      </div>

      <!-- Plan catalog table (union of config + live, keyed by planid) -->
      <section data-testid="billing-plans">
        <h3 class="mb-3 text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.billing.plans.title') }}
        </h3>
        <div
          class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <DataTable
            :columns="columns"
            :rows="planRows"
            row-key="planid"
            :empty-text="t('web.admin.billing.plans.empty')"
            testid="billing-plans-table">
            <template #cell-planid="{ row }">
              <span class="font-mono text-sm text-gray-900 dark:text-white">{{ row.planid }}</span>
            </template>
            <template #cell-status="{ row }">
              <span
                class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
                :class="statusBadgeClass(row.status)">
                {{ t(`web.admin.billing.status.${row.status}`) }}
              </span>
              <span
                v-if="row.fields.length"
                class="ml-2 font-mono text-xs text-gray-500 dark:text-gray-400">
                {{ row.fields.join(', ') }}
              </span>
            </template>
            <template #cell-actions="{ row }">
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-800"
                :data-testid="`billing-diff-${row.planid}`"
                @click="openDiff(row.planid)">
                <OIcon
                  collection="heroicons"
                  name="rectangle-group"
                  size="3" />
                {{ t('web.admin.billing.plans.viewDiff') }}
              </button>
            </template>
          </DataTable>
        </div>
      </section>
    </div>

    <!-- Side-by-side config vs live diff -->
    <DetailDrawer
      v-model:open="drawerOpen"
      :title="t('web.admin.billing.diff.title', { planid: selectedPlanid ?? '' })"
      :subtitle="t('web.admin.billing.diff.subtitle')"
      testid="billing-diff-drawer">
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div>
          <h4 class="mb-2 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.billing.diff.config') }}
          </h4>
          <div
            v-if="selectedConfig"
            class="rounded-lg border border-gray-200 bg-white p-3 dark:border-gray-800 dark:bg-gray-900">
            <JsonViewer
              :data="selectedConfig"
              :expand-depth="2"
              testid="billing-diff-config-json" />
          </div>
          <p
            v-else
            class="rounded-lg border border-dashed border-gray-300 px-3 py-4 text-sm text-gray-500 dark:border-gray-700 dark:text-gray-400"
            data-testid="billing-diff-config-absent">
            {{ t('web.admin.billing.diff.absentConfig') }}
          </p>
        </div>
        <div>
          <h4 class="mb-2 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.billing.diff.live') }}
          </h4>
          <div
            v-if="selectedLive"
            class="rounded-lg border border-gray-200 bg-white p-3 dark:border-gray-800 dark:bg-gray-900">
            <JsonViewer
              :data="selectedLive"
              :expand-depth="2"
              testid="billing-diff-live-json" />
          </div>
          <p
            v-else
            class="rounded-lg border border-dashed border-gray-300 px-3 py-4 text-sm text-gray-500 dark:border-gray-700 dark:text-gray-400"
            data-testid="billing-diff-live-absent">
            {{ t('web.admin.billing.diff.absentLive') }}
          </p>
        </div>
      </div>
    </DetailDrawer>
  </div>
</template>
