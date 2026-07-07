<!-- src/apps/admin/views/AdminDomainToolbox.vue -->

<script setup lang="ts">
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import {
    AdminConfirmDialog,
    DataTable,
    JsonViewer,
    KitPagination,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminDomainToolbox } from '@/apps/admin/stores/useAdminDomainToolbox';
  import type { ColonelOrphanedDomain } from '@/schemas/api/account/responses/colonel-domaintoolbox';
  import type {
    ColonelDomainProbeDetails,
    ColonelDomainRepairDetails,
    ColonelDomainTransferDetails,
  } from '@/schemas/api/account/responses/colonel-domaintoolbox';
  import {
    colonelDomainProbeResponseSchema,
    colonelDomainRepairResponseSchema,
    colonelDomainTransferResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-domaintoolbox';
  import { colonelDomainVerifyResponseSchema } from '@/schemas/api/internal/responses/colonel-domains';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Domain Toolbox (ticket #43) — the Phase-3 payoff that surfaces the CLI-only
   * domain toolbox (`bin/ots domains {orphaned,probe,repair,transfer}`) in the
   * browser, built fresh on the Slice-3 template (no `src/apps/colonel/*` /
   * `colonelInfoStore`). Distinct `domaintoolbox` namespace — does NOT touch
   * Slice-4's AdminDomains.vue.
   *
   * - ORPHANED SCAN (read-only): DataTable + KitPagination over {@link
   *   useAdminDomainToolbox} (`GET /api/colonel/domains/orphaned`, a bounded scan).
   *   Each row seeds the repair form.
   * - PROBE (read-only): `GET /api/colonel/domains/:extid/probe` — HTTPS + TLS
   *   diagnostics with an honest health classification.
   * - RE-VERIFY (reuse): reuses the Slice-4 `/api/colonel/domains/:extid/verify`
   *   endpoint + op — NOT duplicated.
   * - REPAIR + TRANSFER (guarded, D4): dry-run PREVIEW first, then APPLY behind an
   *   {@link AdminConfirmDialog} typed-confirmation (retype the domain extid). The
   *   mutations are audited SERVER-SIDE by the ops (CONTRACT 4).
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  // ---- Orphaned scan (read-only list) ---------------------------------------

  const store = useAdminDomainToolbox();
  const { orphaned, pagination, loading, error } = storeToRefs(store);

  const orphanColumns = computed<DataTableColumn<ColonelOrphanedDomain>[]>(() => [
    { key: 'display_domain', label: t('web.admin.domaintoolbox.orphaned.columns.domain') },
    { key: 'verification_state', label: t('web.admin.domaintoolbox.orphaned.columns.state') },
    { key: 'verified', label: t('web.admin.domaintoolbox.orphaned.columns.verified'), align: 'center' },
    { key: 'created', label: t('web.admin.domaintoolbox.orphaned.columns.created') },
    { key: 'actions', label: t('web.admin.domaintoolbox.orphaned.columns.actions'), align: 'right' },
  ]);

  async function fetchOrphaned(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // Failure captured in store.error; the banner + retry handle it.
    }
  }

  function onOrphanPageChange(targetPage: number): void {
    fetchOrphaned(targetPage);
  }

  function onOrphanPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchOrphaned(1);
  }

  // ---- Diagnostics: probe + re-verify ---------------------------------------

  const probeExtid = ref('');
  const probeRecordDomain = ref('');
  const probeDetails = ref<ColonelDomainProbeDetails | null>(null);

  const {
    loading: probeLoading,
    error: probeError,
    run: runProbe,
    reset: resetProbe,
  } = useAdminMutation(async (extid: string) => {
    probeDetails.value = null;
    const response = await $api.get(
      `/api/colonel/domains/${encodeURIComponent(extid)}/probe`
    );
    const parsed = gracefulParse(
      colonelDomainProbeResponseSchema,
      response.data,
      'ColonelDomainProbeResponse'
    );
    if (parsed.ok) {
      probeDetails.value = parsed.data.details ?? null;
      probeRecordDomain.value = parsed.data.record?.display_domain ?? extid;
    }
  });

  async function onProbe(): Promise<void> {
    const extid = probeExtid.value.trim();
    if (!extid) return;
    resetProbe();
    await runProbe(extid);
  }

  /** Health badge colour keyed by the op's classification. */
  function healthBadgeClass(health: string): string {
    switch (health) {
      case 'healthy':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'ssl_expiring_soon':
      case 'http_error':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      default:
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
    }
  }

  // Re-verify REUSES the Slice-4 endpoint + op (no duplication).
  const {
    loading: verifyLoading,
    error: verifyError,
    run: runVerify,
    reset: resetVerify,
  } = useAdminMutation(async (extid: string) => {
    const response = await $api.post(
      `/api/colonel/domains/${encodeURIComponent(extid)}/verify`
    );
    gracefulParse(
      colonelDomainVerifyResponseSchema,
      response.data,
      'ColonelDomainVerifyResponse'
    );
  });

  async function onReverify(): Promise<void> {
    const extid = probeExtid.value.trim();
    if (!extid) return;
    resetVerify();
    const ok = await runVerify(extid);
    if (ok) {
      notifications.show(t('web.admin.domaintoolbox.reverify.success'), 'success');
      fetchOrphaned(pagination.value?.page ?? 1);
    }
  }

  // ---- Repair (guarded: dry-run preview → typed-confirm apply) ---------------

  const repairExtid = ref('');
  const repairOrgId = ref('');
  const repairPlan = ref<ColonelDomainRepairDetails | null>(null);
  const repairDialogOpen = ref(false);

  /** Build the repair request body; org_id only when supplied. */
  function repairBody(dryRun: boolean): Record<string, unknown> {
    const body: Record<string, unknown> = { dry_run: dryRun };
    const org = repairOrgId.value.trim();
    if (org) body.org_id = org;
    return body;
  }

  const {
    loading: repairPreviewLoading,
    error: repairPreviewError,
    run: runRepairPreview,
    reset: resetRepairPreview,
  } = useAdminMutation(async (extid: string) => {
    repairPlan.value = null;
    const response = await $api.post(
      `/api/colonel/domains/${encodeURIComponent(extid)}/repair`,
      repairBody(true)
    );
    const parsed = gracefulParse(
      colonelDomainRepairResponseSchema,
      response.data,
      'ColonelDomainRepairResponse'
    );
    if (parsed.ok) repairPlan.value = parsed.data.details ?? null;
  });

  const {
    loading: repairApplyLoading,
    error: repairApplyError,
    run: runRepairApply,
    reset: resetRepairApply,
  } = useAdminMutation(async (extid: string) => {
    const response = await $api.post(
      `/api/colonel/domains/${encodeURIComponent(extid)}/repair`,
      repairBody(false)
    );
    gracefulParse(
      colonelDomainRepairResponseSchema,
      response.data,
      'ColonelDomainRepairResponse'
    );
  });

  async function onRepairPreview(): Promise<void> {
    const extid = repairExtid.value.trim();
    if (!extid) return;
    resetRepairPreview();
    await runRepairPreview(extid);
  }

  /** True when the previewed plan actually has repairs to apply. */
  const repairApplicable = computed(
    () => repairPlan.value?.status === 'planned' && (repairPlan.value?.issues.length ?? 0) > 0
  );

  function requestRepairApply(): void {
    resetRepairApply();
    repairDialogOpen.value = true;
  }

  async function onRepairConfirm(): Promise<void> {
    const extid = repairExtid.value.trim();
    const ok = await runRepairApply(extid);
    if (!ok) return;
    repairDialogOpen.value = false;
    notifications.show(t('web.admin.domaintoolbox.repair.success'), 'success');
    repairPlan.value = null;
    fetchOrphaned(pagination.value?.page ?? 1);
  }

  function onRepairCancel(): void {
    repairDialogOpen.value = false;
    resetRepairApply();
  }

  /** Row action: seed the repair form from an orphaned row. */
  function seedRepair(row: ColonelOrphanedDomain): void {
    repairExtid.value = row.extid;
    repairOrgId.value = '';
    repairPlan.value = null;
    resetRepairPreview();
    probeExtid.value = row.extid;
  }

  // ---- Transfer (guarded: dry-run preview → typed-confirm apply) -------------

  const transferExtid = ref('');
  const transferToOrg = ref('');
  const transferFromOrg = ref('');
  const transferPlan = ref<ColonelDomainTransferDetails | null>(null);
  const transferDialogOpen = ref(false);

  function transferBody(dryRun: boolean): Record<string, unknown> {
    const body: Record<string, unknown> = {
      dry_run: dryRun,
      to_org: transferToOrg.value.trim(),
    };
    const from = transferFromOrg.value.trim();
    if (from) body.from_org = from;
    return body;
  }

  const {
    loading: transferPreviewLoading,
    error: transferPreviewError,
    run: runTransferPreview,
    reset: resetTransferPreview,
  } = useAdminMutation(async (extid: string) => {
    transferPlan.value = null;
    const response = await $api.post(
      `/api/colonel/domains/${encodeURIComponent(extid)}/transfer`,
      transferBody(true)
    );
    const parsed = gracefulParse(
      colonelDomainTransferResponseSchema,
      response.data,
      'ColonelDomainTransferResponse'
    );
    if (parsed.ok) transferPlan.value = parsed.data.details ?? null;
  });

  const {
    loading: transferApplyLoading,
    error: transferApplyError,
    run: runTransferApply,
    reset: resetTransferApply,
  } = useAdminMutation(async (extid: string) => {
    const response = await $api.post(
      `/api/colonel/domains/${encodeURIComponent(extid)}/transfer`,
      transferBody(false)
    );
    gracefulParse(
      colonelDomainTransferResponseSchema,
      response.data,
      'ColonelDomainTransferResponse'
    );
  });

  const transferReady = computed(
    () => transferExtid.value.trim() !== '' && transferToOrg.value.trim() !== ''
  );

  async function onTransferPreview(): Promise<void> {
    if (!transferReady.value) return;
    resetTransferPreview();
    await runTransferPreview(transferExtid.value.trim());
  }

  const transferApplicable = computed(() => transferPlan.value?.status === 'planned');

  function requestTransferApply(): void {
    resetTransferApply();
    transferDialogOpen.value = true;
  }

  async function onTransferConfirm(): Promise<void> {
    const extid = transferExtid.value.trim();
    const ok = await runTransferApply(extid);
    if (!ok) return;
    transferDialogOpen.value = false;
    notifications.show(t('web.admin.domaintoolbox.transfer.success'), 'success');
    transferPlan.value = null;
    fetchOrphaned(pagination.value?.page ?? 1);
  }

  function onTransferCancel(): void {
    transferDialogOpen.value = false;
    resetTransferApply();
  }

  onMounted(() => fetchOrphaned(1));
</script>

<template>
  <div class="mx-auto max-w-6xl space-y-8">
    <!-- Page header -->
    <div>
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.domaintoolbox.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domaintoolbox.description') }}
      </p>
    </div>

    <!-- ===== Orphaned scan (read-only) ===================================== -->
    <section data-testid="orphaned-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.domaintoolbox.orphaned.title') }}
      </h3>
      <p class="mb-3 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domaintoolbox.orphaned.description') }}
      </p>

      <div
        v-if="error"
        class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
        role="alert"
        data-testid="orphaned-error">
        <span class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.domaintoolbox.orphaned.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="fetchOrphaned(1)">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.domaintoolbox.retry') }}
        </button>
      </div>

      <div
        class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <DataTable
          :columns="orphanColumns"
          :rows="orphaned"
          row-key="domain_id"
          :loading="loading"
          :empty-text="t('web.admin.domaintoolbox.orphaned.empty')"
          testid="orphaned-table">
          <template #cell-display_domain="{ row }">
            <span class="font-mono text-gray-900 dark:text-white">{{ row.display_domain }}</span>
          </template>
          <template #cell-verified="{ row }">
            <OIcon
              v-if="row.verified"
              collection="heroicons"
              name="check-circle"
              size="5"
              class="inline text-green-600 dark:text-green-400" />
            <span v-else class="text-gray-400 dark:text-gray-600">—</span>
          </template>
          <template #cell-created="{ row }">
            {{ row.created ? formatDisplayDateTime(row.created) : '—' }}
          </template>
          <template #cell-actions="{ row }">
            <button
              type="button"
              :data-testid="`orphaned-repair-${row.extid}`"
              class="text-sm font-medium text-brand-600 hover:text-brand-800 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-brand-400 dark:hover:text-brand-300"
              @click="seedRepair(row)">
              {{ t('web.admin.domaintoolbox.orphaned.repairAction') }}
            </button>
          </template>
        </DataTable>
      </div>

      <KitPagination
        v-if="pagination"
        :pagination="pagination"
        :loading="loading"
        class="mt-4"
        @update:page="onOrphanPageChange"
        @update:per-page="onOrphanPerPageChange" />
    </section>

    <!-- ===== Diagnostics: probe + re-verify (read-only / reuse) =========== -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="probe-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.domaintoolbox.probe.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domaintoolbox.probe.description') }}
      </p>

      <div class="flex flex-wrap items-end gap-3">
        <div class="flex-1 min-w-[16rem]">
          <label
            for="probe-extid"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domaintoolbox.fields.extid') }}
          </label>
          <input
            id="probe-extid"
            v-model="probeExtid"
            type="text"
            data-testid="probe-extid-input"
            :placeholder="t('web.admin.domaintoolbox.fields.extidPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="button"
          data-testid="probe-run"
          :disabled="!probeExtid.trim() || probeLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50"
          @click="onProbe">
          <OIcon
            collection="heroicons"
            :name="probeLoading ? 'arrow-path' : 'signal'"
            size="4"
            :class="probeLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
          {{ t('web.admin.domaintoolbox.probe.button') }}
        </button>
        <button
          type="button"
          data-testid="reverify-run"
          :disabled="!probeExtid.trim() || verifyLoading"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="onReverify">
          <OIcon
            collection="heroicons"
            :name="verifyLoading ? 'arrow-path' : 'shield-check'"
            size="4"
            :class="verifyLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
          {{ t('web.admin.domaintoolbox.reverify.button') }}
        </button>
      </div>

      <p
        v-if="probeError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="probe-error">
        {{ probeError }}
      </p>
      <p
        v-if="verifyError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="reverify-error">
        {{ verifyError }}
      </p>

      <!-- Probe result -->
      <div
        v-if="probeDetails"
        class="mt-5 space-y-4 border-t border-gray-100 pt-4 dark:border-gray-800"
        data-testid="probe-result">
        <div class="flex items-center gap-3">
          <span class="text-sm text-gray-500 dark:text-gray-400">{{ t('web.admin.domaintoolbox.probe.healthLabel') }}:</span>
          <span
            :class="[
              'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
              healthBadgeClass(probeDetails.health),
            ]"
            data-testid="probe-health">
            {{ probeDetails.health }}
          </span>
          <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{ probeRecordDomain }}</span>
        </div>
        <JsonViewer
          :data="probeDetails"
          :expand-depth="2"
          testid="probe-json" />
      </div>
    </section>

    <!-- ===== Repair (guarded) ============================================= -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="repair-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.domaintoolbox.repair.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domaintoolbox.repair.description') }}
      </p>

      <div class="flex flex-wrap items-end gap-3">
        <div class="flex-1 min-w-[14rem]">
          <label
            for="repair-extid"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domaintoolbox.fields.extid') }}
          </label>
          <input
            id="repair-extid"
            v-model="repairExtid"
            type="text"
            data-testid="repair-extid-input"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <div class="flex-1 min-w-[14rem]">
          <label
            for="repair-orgid"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domaintoolbox.repair.orgIdLabel') }}
          </label>
          <input
            id="repair-orgid"
            v-model="repairOrgId"
            type="text"
            data-testid="repair-orgid-input"
            :placeholder="t('web.admin.domaintoolbox.repair.orgIdPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="button"
          data-testid="repair-preview"
          :disabled="!repairExtid.trim() || repairPreviewLoading"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="onRepairPreview">
          {{ t('web.admin.domaintoolbox.preview') }}
        </button>
      </div>

      <p
        v-if="repairPreviewError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="repair-preview-error">
        {{ repairPreviewError }}
      </p>

      <!-- Repair plan -->
      <div
        v-if="repairPlan"
        class="mt-5 border-t border-gray-100 pt-4 dark:border-gray-800"
        data-testid="repair-plan">
        <p class="mb-2 text-sm text-gray-700 dark:text-gray-300">
          {{ t('web.admin.domaintoolbox.repair.statusLabel') }}:
          <span class="font-mono font-medium" data-testid="repair-status">{{ repairPlan.status }}</span>
        </p>
        <ul
          v-if="repairPlan.issues.length"
          class="ml-4 list-disc space-y-1 text-sm text-gray-700 dark:text-gray-300">
          <li v-for="(issue, i) in repairPlan.issues" :key="i">{{ issue }}</li>
        </ul>
        <p v-else class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.domaintoolbox.repair.noIssues') }}
        </p>

        <button
          v-if="repairApplicable"
          type="button"
          data-testid="repair-apply"
          class="mt-4 inline-flex items-center gap-1 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 focus:outline-none focus:ring-2 focus:ring-amber-500"
          @click="requestRepairApply">
          <OIcon
            collection="heroicons"
            name="cog-6-tooth"
            size="4" />
          {{ t('web.admin.domaintoolbox.repair.applyButton') }}
        </button>
      </div>
    </section>

    <!-- ===== Transfer (guarded) =========================================== -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="transfer-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.domaintoolbox.transfer.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domaintoolbox.transfer.description') }}
      </p>

      <div class="grid gap-3 sm:grid-cols-3">
        <div>
          <label
            for="transfer-extid"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domaintoolbox.fields.extid') }}
          </label>
          <input
            id="transfer-extid"
            v-model="transferExtid"
            type="text"
            data-testid="transfer-extid-input"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <div>
          <label
            for="transfer-to"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domaintoolbox.transfer.toOrgLabel') }}
          </label>
          <input
            id="transfer-to"
            v-model="transferToOrg"
            type="text"
            data-testid="transfer-toorg-input"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <div>
          <label
            for="transfer-from"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domaintoolbox.transfer.fromOrgLabel') }}
          </label>
          <input
            id="transfer-from"
            v-model="transferFromOrg"
            type="text"
            data-testid="transfer-fromorg-input"
            :placeholder="t('web.admin.domaintoolbox.transfer.fromOrgPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
      </div>

      <button
        type="button"
        data-testid="transfer-preview"
        :disabled="!transferReady || transferPreviewLoading"
        class="mt-3 inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
        @click="onTransferPreview">
        {{ t('web.admin.domaintoolbox.preview') }}
      </button>

      <p
        v-if="transferPreviewError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="transfer-preview-error">
        {{ transferPreviewError }}
      </p>

      <!-- Transfer plan -->
      <div
        v-if="transferPlan"
        class="mt-5 border-t border-gray-100 pt-4 text-sm dark:border-gray-800"
        data-testid="transfer-plan">
        <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.domaintoolbox.transfer.from') }}</dt>
            <dd class="font-mono text-gray-900 dark:text-white">
              {{ transferPlan.from_org_id ? `${transferPlan.from_org_name || '—'} (${transferPlan.from_org_id})` : t('web.admin.domaintoolbox.transfer.orphaned') }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.domaintoolbox.transfer.to') }}</dt>
            <dd class="font-mono text-gray-900 dark:text-white">
              {{ transferPlan.to_org_name || '—' }} ({{ transferPlan.to_org_id }})
            </dd>
          </div>
        </dl>

        <button
          v-if="transferApplicable"
          type="button"
          data-testid="transfer-apply"
          class="mt-4 inline-flex items-center gap-1 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500"
          @click="requestTransferApply">
          <OIcon
            collection="heroicons"
            name="arrow-right"
            size="4" />
          {{ t('web.admin.domaintoolbox.transfer.applyButton') }}
        </button>
      </div>
    </section>

    <!-- Typed-confirmation gates (destructive verbs). -->
    <AdminConfirmDialog
      v-model:open="repairDialogOpen"
      :title="t('web.admin.domaintoolbox.repair.confirmTitle')"
      :description="t('web.admin.domaintoolbox.repair.confirmDescription', { domain: repairExtid.trim() })"
      :confirm-token="repairExtid.trim()"
      variant="danger"
      :confirm-text="t('web.admin.domaintoolbox.repair.applyButton')"
      :loading="repairApplyLoading"
      :error="repairApplyError"
      @confirm="onRepairConfirm"
      @cancel="onRepairCancel" />

    <AdminConfirmDialog
      v-model:open="transferDialogOpen"
      :title="t('web.admin.domaintoolbox.transfer.confirmTitle')"
      :description="t('web.admin.domaintoolbox.transfer.confirmDescription', { domain: transferExtid.trim() })"
      :confirm-token="transferExtid.trim()"
      variant="danger"
      :confirm-text="t('web.admin.domaintoolbox.transfer.applyButton')"
      :loading="transferApplyLoading"
      :error="transferApplyError"
      @confirm="onTransferConfirm"
      @cancel="onTransferCancel" />
  </div>
</template>
