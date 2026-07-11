<!-- src/apps/admin/components/AdminCustomerSessionsSection.vue -->

<script setup lang="ts">

  import { AdminConfirmDialog, DataTable } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminCustomerSessions } from '@/apps/admin/stores/useAdminCustomerSessions';
  import type { AdminCustomerSession } from '@/schemas/api/internal/responses/colonel-customer-sessions';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Per-customer active-sessions panel (spec 40) — the SIDECAR view mounted
   * inside {@link AdminCustomerDetail}. Reads one customer's SessionMetadata
   * safe_dump rows via {@link useAdminCustomerSessions}; there is NO token /
   * payload / email field on those rows (the positive allow-list is the feature's
   * security boundary), so this table physically cannot render one.
   *
   * Revoke logs that user out mid-flight, so it is gated by
   * {@link AdminConfirmDialog} (danger) and audited SERVER-SIDE.
   */
  const props = defineProps<{
    /** The customer's public id (extid, 'ur…'), forwarded from the detail view. */
    userId: string;
  }>();

  const { t } = useI18n();
  const notifications = useNotificationsStore();

  const store = useAdminCustomerSessions();
  const { sessions, loading, error, validationError } = storeToRefs(store);

  const loadFailed = computed(
    () => error.value !== null || validationError.value !== null
  );

  const columns = computed<DataTableColumn<AdminCustomerSession>[]>(() => [
    { key: 'last_activity_at', label: t('web.admin.customers.detail.sessions.columns.lastActivity') },
    { key: 'ip_address', label: t('web.admin.customers.detail.sessions.columns.ipAddress') },
    { key: 'user_agent', label: t('web.admin.customers.detail.sessions.columns.device') },
    { key: 'auth_method', label: t('web.admin.customers.detail.sessions.columns.authMethod') },
    { key: 'actions', label: t('web.admin.customers.detail.sessions.columns.actions'), align: 'right' },
  ]);

  /** Epoch fields arrive as bare Unix-second numbers. */
  function activityLabel(epoch: number | null): string {
    if (!epoch) return t('web.admin.customers.detail.sessions.unknown');
    return formatDisplayDateTime(new Date(epoch * 1000));
  }

  function load(): void {
    store.fetchForCustomer(props.userId).catch(() => {
      // Failure surfaces via store.error → the error state below. Swallow so it
      // doesn't become an unhandled rejection.
    });
  }

  // Refetch if the detail component is reused across a different customer id.
  watch(() => props.userId, load);
  onMounted(load);

  // ---- Guarded revoke -------------------------------------------------------

  const revokeDialogOpen = ref(false);
  /** The session id the confirm dialog is gating (request target). */
  const revokeTarget = ref('');

  const {
    loading: revokeLoading,
    error: revokeError,
    run: runRevoke,
    reset: resetRevoke,
  } = useAdminMutation(async () => {
    if (!revokeTarget.value) throw new Error('No session selected');
    // The store optimistically drops the row on a 2xx; a failure throws before
    // the drop, so useAdminMutation captures it and the row stays for retry.
    await store.revoke(props.userId, revokeTarget.value);
  });

  function requestRevoke(sessionId: string): void {
    revokeTarget.value = sessionId;
    resetRevoke();
    revokeDialogOpen.value = true;
  }

  async function onRevokeConfirm(): Promise<void> {
    const ok = await runRevoke();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.
    revokeDialogOpen.value = false;
    revokeTarget.value = '';
    notifications.show(t('web.admin.customers.detail.sessions.revoke.success'), 'success');
  }

  function onRevokeCancel(): void {
    revokeDialogOpen.value = false;
    revokeTarget.value = '';
    resetRevoke();
  }

  // ---- Guarded revoke-all (offboarding / takeover) --------------------------

  const revokeAllDialogOpen = ref(false);
  /** Kill count from the last successful revoke-all (drives the success toast). */
  const lastRevokedCount = ref(0);
  /** True when the last revoke-all's untracked sweep was truncated by the cap. */
  const lastScanCapped = ref(false);

  const {
    loading: revokeAllLoading,
    error: revokeAllError,
    run: runRevokeAll,
    reset: resetRevokeAll,
  } = useAdminMutation(async () => {
    // run() only returns a boolean, so stash the server's counts for the toast.
    const record = await store.revokeAll(props.userId);
    lastRevokedCount.value = record.blobs_deleted;
    lastScanCapped.value = record.scan_capped;
  });

  function requestRevokeAll(): void {
    resetRevokeAll();
    revokeAllDialogOpen.value = true;
  }

  async function onRevokeAllConfirm(): Promise<void> {
    const ok = await runRevokeAll();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.
    revokeAllDialogOpen.value = false;
    // Tracked sessions are always killed; a capped sweep may leave a pre-sidecar
    // one alive, so warn instead of a clean success in that case.
    if (lastScanCapped.value) {
      notifications.show(
        t('web.admin.customers.detail.sessions.revokeAll.capped', {
          count: lastRevokedCount.value,
        }),
        'warning'
      );
    } else {
      notifications.show(
        t('web.admin.customers.detail.sessions.revokeAll.success', {
          count: lastRevokedCount.value,
        }),
        'success'
      );
    }
  }

  function onRevokeAllCancel(): void {
    revokeAllDialogOpen.value = false;
    resetRevokeAll();
  }
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="sessions-section">
    <div class="flex items-center justify-between gap-4 border-b border-gray-200 px-6 py-4 dark:border-gray-800">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.customers.detail.sessions.title') }}
        <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400">({{ sessions.length }})</span>
      </h3>
      <!-- Offboarding / takeover: kills EVERY session, incl. untracked ones. -->
      <button
        type="button"
        data-testid="sessions-revoke-all"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/40"
        :disabled="loading"
        @click="requestRevokeAll">
        <OIcon
          collection="heroicons"
          name="shield-exclamation"
          size="4" />
        {{ t('web.admin.customers.detail.sessions.revokeAll.button') }}
      </button>
    </div>

    <!-- Load error (network/HTTP or contract mismatch). -->
    <div
      v-if="loadFailed"
      class="flex items-center justify-between gap-4 px-6 py-4"
      role="alert"
      data-testid="sessions-section-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.customers.detail.sessions.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="load">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.customers.detail.retry') }}
      </button>
    </div>

    <DataTable
      v-else
      :columns="columns"
      :rows="sessions"
      row-key="session_id"
      :loading="loading"
      :empty-text="t('web.admin.customers.detail.sessions.empty')"
      testid="sessions-section-table">
      <template #cell-last_activity_at="{ row }">
        {{ activityLabel(row.last_activity_at) }}
      </template>

      <template #cell-ip_address="{ row }">
        <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{ row.ip_address || '—' }}</span>
      </template>

      <template #cell-user_agent="{ row }">
        <span class="text-sm break-words text-gray-700 dark:text-gray-300">{{ row.user_agent || '—' }}</span>
      </template>

      <template #cell-auth_method="{ row }">
        <span class="text-sm text-gray-700 dark:text-gray-300">{{ row.auth_method || '—' }}</span>
      </template>

      <template #cell-actions="{ row }">
        <button
          type="button"
          :data-testid="`session-revoke-${row.session_id}`"
          class="text-sm font-medium text-red-600 hover:text-red-800 focus:ring-2 focus:ring-red-500 focus:outline-none dark:text-red-400 dark:hover:text-red-300"
          @click="requestRevoke(row.session_id)">
          {{ t('web.admin.customers.detail.sessions.revoke.button') }}
        </button>
      </template>
    </DataTable>

    <!-- Guarded revoke (danger). Revoking logs the user out mid-flight. -->
    <AdminConfirmDialog
      v-model:open="revokeDialogOpen"
      :title="t('web.admin.customers.detail.sessions.revoke.confirmTitle')"
      :description="t('web.admin.customers.detail.sessions.revoke.confirmDescription')"
      variant="danger"
      :confirm-text="t('web.admin.customers.detail.sessions.revoke.button')"
      :loading="revokeLoading"
      :error="revokeError"
      @confirm="onRevokeConfirm"
      @cancel="onRevokeCancel" />

    <!-- Guarded revoke-all (danger). Logs the customer out of EVERY device. -->
    <AdminConfirmDialog
      v-model:open="revokeAllDialogOpen"
      :title="t('web.admin.customers.detail.sessions.revokeAll.confirmTitle')"
      :description="t('web.admin.customers.detail.sessions.revokeAll.confirmDescription')"
      variant="danger"
      :confirm-token="props.userId"
      :confirm-text="t('web.admin.customers.detail.sessions.revokeAll.button')"
      :loading="revokeAllLoading"
      :error="revokeAllError"
      @confirm="onRevokeAllConfirm"
      @cancel="onRevokeAllCancel" />
  </section>
</template>
