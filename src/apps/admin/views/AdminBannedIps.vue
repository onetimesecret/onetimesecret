<!-- src/apps/admin/views/AdminBannedIps.vue -->

<script setup lang="ts">

  import { AdminConfirmDialog, DataTable, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { BannedIP } from '@/schemas/api/internal/responses/colonel';
  import {
    bannedIPsResponseSchema,
    colonelBanIpResponseSchema,
    colonelUnbanIpResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-bannedips';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * BannedIPs screen (ticket #33) — list + guarded ban/unban, the Phase-2 parity
   * port of the hand-rolled `ColonelBannedIPs.vue` rebuilt on the Slice-3 template
   * (no `src/apps/colonel/*` / `colonelInfoStore` imports).
   *
   * - LIST via {@link useResourceFetch} against `GET /api/colonel/banned-ips`
   *   (a bounded index read — #2211, no server pagination), REUSING the frozen
   *   `bannedIPsResponseSchema` (CONTRACT 3). Rendered with the kit DataTable.
   * - The hand-rolled add-IP form is replaced with kit-styled inputs + the shared
   *   {@link AdminConfirmDialog}.
   * - GUARDED ban + unban (D4): both go through {@link useAdminMutation} +
   *   typed-confirmation (retype the IP) — ban is `POST /banned-ips`, unban is
   *   `DELETE /banned-ips/:ip`. Both are audited SERVER-SIDE by the extracted
   *   ops ({@link Onetime::Operations::BanIP} / `UnbanIP`); nothing here logs.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  // ---- List -----------------------------------------------------------------

  const {
    data: listData,
    loading,
    error,
    validationError,
    load: loadList,
  } = useResourceFetch({
    url: '/api/colonel/banned-ips',
    schema: bannedIPsResponseSchema,
    context: 'BannedIPsResponse',
  });

  const bannedIPs = computed<BannedIP[]>(() => listData.value?.details?.banned_ips ?? []);
  const currentIP = computed(() => listData.value?.details?.current_ip ?? '');
  const totalCount = computed(() => listData.value?.details?.total_count ?? 0);
  const loadFailed = computed(() => error.value !== null || validationError.value !== null);

  function reloadList(): void {
    loadList().catch(() => {});
  }

  const columns = computed<DataTableColumn<BannedIP>[]>(() => [
    { key: 'ip_address', label: t('web.admin.bannedIps.columns.ipAddress') },
    { key: 'reason', label: t('web.admin.bannedIps.columns.reason') },
    { key: 'banned_at', label: t('web.admin.bannedIps.columns.bannedAt') },
    { key: 'banned_by', label: t('web.admin.bannedIps.columns.bannedBy') },
    { key: 'actions', label: t('web.admin.bannedIps.columns.actions'), align: 'right' },
  ]);

  /** banned_at is Unix seconds (bannedIPSchema keeps it a bare number). */
  function bannedAtLabel(bannedAt: number): string {
    return formatDisplayDateTime(new Date(bannedAt * 1000));
  }

  // ---- Add-IP form ----------------------------------------------------------

  const newIP = ref('');
  const newReason = ref('');
  const showBanForm = ref(false);

  function toggleBanForm(): void {
    showBanForm.value = !showBanForm.value;
  }

  function quickBanCurrent(): void {
    newIP.value = currentIP.value;
    newReason.value = '';
    showBanForm.value = true;
  }

  // ---- Guarded mutations (D4) ----------------------------------------------

  type ActionKey = 'ban' | 'unban';

  const dialogOpen = ref(false);
  const activeAction = ref<ActionKey | null>(null);
  /** The IP the confirm dialog is gating (retype token + request target). */
  const targetIp = ref('');
  /** Reason captured at ban-request time (the form may change after). */
  const targetReason = ref('');

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    const ip = targetIp.value;
    if (!ip) throw new Error('No IP selected');

    if (activeAction.value === 'ban') {
      const response = await $api.post('/api/colonel/banned-ips', {
        ip_address: ip,
        reason: targetReason.value || undefined,
      });
      // A 2xx means the ban was applied server-side regardless of ack shape; the
      // parse keeps the contract a live tripwire without failing the action.
      gracefulParse(colonelBanIpResponseSchema, response.data, 'ColonelBanIpResponse');
    } else {
      const response = await $api.delete(`/api/colonel/banned-ips/${encodeURIComponent(ip)}`);
      gracefulParse(colonelUnbanIpResponseSchema, response.data, 'ColonelUnbanIpResponse');
    }
  });

  const dialogConfig = computed(() => {
    if (activeAction.value === 'ban') {
      return {
        title: t('web.admin.bannedIps.ban.confirmTitle'),
        description: t('web.admin.bannedIps.ban.confirmDescription', { ip: targetIp.value }),
        confirmText: t('web.admin.bannedIps.ban.button'),
        variant: 'danger' as const,
      };
    }
    return {
      title: t('web.admin.bannedIps.unban.confirmTitle'),
      description: t('web.admin.bannedIps.unban.confirmDescription', { ip: targetIp.value }),
      confirmText: t('web.admin.bannedIps.unban.button'),
      variant: 'default' as const,
    };
  });

  function requestBan(): void {
    const ip = newIP.value.trim();
    if (!ip) return; // Nothing to confirm without an IP.
    activeAction.value = 'ban';
    targetIp.value = ip;
    targetReason.value = newReason.value.trim();
    resetMutation();
    dialogOpen.value = true;
  }

  function requestUnban(ip: string): void {
    activeAction.value = 'unban';
    targetIp.value = ip;
    targetReason.value = '';
    resetMutation();
    dialogOpen.value = true;
  }

  async function onConfirm(): Promise<void> {
    const action = activeAction.value;
    if (!action) return;

    const ok = await runMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;

    if (action === 'ban') {
      notifications.show(t('web.admin.bannedIps.ban.success', { ip: targetIp.value }), 'success');
      newIP.value = '';
      newReason.value = '';
      showBanForm.value = false;
    } else {
      notifications.show(t('web.admin.bannedIps.unban.success', { ip: targetIp.value }), 'success');
    }

    activeAction.value = null;
    reloadList();
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeAction.value = null;
    resetMutation();
  }

  onMounted(reloadList);
</script>

<template>
  <div class="mx-auto max-w-5xl">
    <!-- Page header -->
    <div class="mb-6 flex flex-wrap items-start justify-between gap-3 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <div>
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ t('web.admin.bannedIps.title') }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.bannedIps.description') }}
        </p>
      </div>
      <button
        type="button"
        data-testid="toggle-ban-form"
        class="inline-flex shrink-0 items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
        @click="toggleBanForm">
        <OIcon
          collection="heroicons"
          :name="showBanForm ? 'x-mark' : 'no-symbol'"
          size="4" />
        {{ showBanForm ? t('web.admin.bannedIps.actions.cancel') : t('web.admin.bannedIps.actions.ban') }}
      </button>
    </div>

    <!-- Error banner -->
    <div
      v-if="loadFailed"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="bannedips-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.bannedIps.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="reloadList">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.bannedIps.list.retry') }}
      </button>
    </div>

    <!-- Current IP + count -->
    <div class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
      <div
        class="flex items-center justify-between gap-3 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 dark:border-blue-900/50 dark:bg-blue-900/20"
        data-testid="current-ip">
        <div class="min-w-0">
          <p class="text-xs font-medium tracking-wider text-blue-700 uppercase dark:text-blue-300">
            {{ t('web.admin.bannedIps.currentIp') }}
          </p>
          <p class="mt-0.5 truncate font-mono text-lg font-semibold text-blue-900 dark:text-blue-100">
            {{ currentIP || '—' }}
          </p>
        </div>
        <button
          v-if="currentIP && currentIP !== 'unknown'"
          type="button"
          data-testid="quick-ban"
          class="shrink-0 rounded px-3 py-1.5 text-sm font-medium text-blue-700 hover:bg-blue-100 focus:ring-2 focus:ring-blue-500 focus:outline-none dark:text-blue-300 dark:hover:bg-blue-800/50"
          @click="quickBanCurrent">
          {{ t('web.admin.bannedIps.actions.quickBan') }}
        </button>
      </div>
      <StatCard
        :label="t('web.admin.bannedIps.stats.total')"
        :value="totalCount"
        icon="no-symbol"
        testid="stat-total" />
    </div>

    <!-- Ban form -->
    <div
      v-if="showBanForm"
      class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="ban-form">
      <h3 class="mb-4 text-sm font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.bannedIps.form.title') }}
      </h3>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label
            for="ban-ip"
            class="mb-1 block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.bannedIps.form.ipLabel') }}
          </label>
          <input
            id="ban-ip"
            v-model="newIP"
            type="text"
            data-testid="ban-ip-input"
            placeholder="203.0.113.4"
            autocomplete="off"
            spellcheck="false"
            class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white"
            @keyup.enter="requestBan" />
        </div>
        <div>
          <label
            for="ban-reason"
            class="mb-1 block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.bannedIps.form.reasonLabel') }}
          </label>
          <input
            id="ban-reason"
            v-model="newReason"
            type="text"
            data-testid="ban-reason-input"
            :placeholder="t('web.admin.bannedIps.form.reasonPlaceholder')"
            class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
      </div>
      <div class="mt-4">
        <button
          type="button"
          data-testid="ban-submit"
          :disabled="!newIP.trim()"
          class="inline-flex items-center gap-1 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 focus:ring-2 focus:ring-red-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-700 dark:hover:bg-red-800"
          @click="requestBan">
          <OIcon
            collection="heroicons"
            name="no-symbol"
            size="4" />
          {{ t('web.admin.bannedIps.form.submit') }}
        </button>
      </div>
    </div>

    <!-- Banned IPs table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="bannedIPs"
        row-key="id"
        :loading="loading"
        :empty-text="t('web.admin.bannedIps.list.empty')"
        testid="bannedips-table">
        <template #cell-ip_address="{ row }">
          <span class="font-mono text-gray-900 dark:text-white">{{ row.ip_address }}</span>
        </template>
        <template #cell-reason="{ row }">
          <span class="text-gray-600 dark:text-gray-400">{{ row.reason || '—' }}</span>
        </template>
        <template #cell-banned_at="{ row }">
          {{ bannedAtLabel(row.banned_at) }}
        </template>
        <template #cell-banned_by="{ row }">
          <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{ row.banned_by || '—' }}</span>
        </template>
        <template #cell-actions="{ row }">
          <button
            type="button"
            :data-testid="`unban-${row.ip_address}`"
            class="text-sm font-medium text-red-600 hover:text-red-800 focus:ring-2 focus:ring-red-500 focus:outline-none dark:text-red-400 dark:hover:text-red-300"
            @click="requestUnban(row.ip_address)">
            {{ t('web.admin.bannedIps.unban.button') }}
          </button>
        </template>
      </DataTable>
    </div>

    <!-- Shared guarded-action dialog (typed-confirmation for ban + unban). -->
    <AdminConfirmDialog
      v-model:open="dialogOpen"
      :title="dialogConfig.title"
      :description="dialogConfig.description"
      :confirm-token="targetIp"
      :variant="dialogConfig.variant"
      :confirm-text="dialogConfig.confirmText"
      :loading="mutationLoading"
      :error="mutationError"
      @confirm="onConfirm"
      @cancel="onCancel" />
  </div>
</template>
