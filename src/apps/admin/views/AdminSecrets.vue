<!-- src/apps/admin/views/AdminSecrets.vue -->

<script setup lang="ts">
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import {
    AdminConfirmDialog,
    DataTable,
    DetailDrawer,
    JsonViewer,
    KitPagination,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { useAdminSecrets } from '@/apps/admin/stores/useAdminSecrets';
  import type { ColonelSecret } from '@/schemas/api/account/responses/colonel';
  import {
    colonelSecretDeleteResponseSchema,
    colonelSecretReceiptResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-secrets';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Secrets screen (ticket #30) — the parity port of the hand-rolled
   * `ColonelSecrets.vue`, rebuilt on the Slice-3 template.
   *
   * - LIST: DataTable + KitPagination over the existing {@link useAdminSecrets}
   *   store (one server page per request; the list endpoint offers no server-side
   *   filter, so — like AdminCustomers — no inert FilterBar is shown).
   * - RECEIPT DRAWER: clicking a row opens a {@link DetailDrawer} that loads
   *   GET /api/colonel/secrets/:secret_id via {@link useResourceFetch} (secret
   *   record + receipt metadata + owner + raw JSON inspector).
   * - GUARDED DELETE (D4): the drawer footer surfaces the destructive delete that
   *   `DELETE /api/colonel/secrets/:secret_id` has always supported but no UI ever
   *   exposed. It is gated by {@link AdminConfirmDialog} typed-confirmation
   *   (retype the secret's short id) in danger mode. On success the list refreshes.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const store = useAdminSecrets();
  const { secrets, pagination, loading, error } = storeToRefs(store);

  const columns = computed<DataTableColumn<ColonelSecret>[]>(() => [
    { key: 'shortid', label: t('web.admin.secrets.columns.shortId') },
    { key: 'state', label: t('web.admin.secrets.columns.state') },
    { key: 'owner', label: t('web.admin.secrets.columns.owner') },
    { key: 'created', label: t('web.admin.secrets.columns.created') },
    { key: 'expiration', label: t('web.admin.secrets.columns.expiration') },
    { key: 'age', label: t('web.admin.secrets.columns.age'), align: 'right' },
  ]);

  /** State badge classes, mirroring the old colonel screen's colour language. */
  function stateBadgeClass(state: string): string {
    switch (state) {
      case 'new':
        return 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
      case 'received':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-200';
      default:
        return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
    }
  }

  function stateLabel(state: string): string {
    return t(`web.admin.secrets.state.${state}`, state);
  }

  /** Age in whole days, matching the legacy screen (`floor(age / 86400)`). */
  function ageInDays(age: number): number {
    return Math.floor(age / 86400);
  }

  // ---- List paging ----------------------------------------------------------

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow so it doesn't become unhandled.
    }
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Receipt drawer -------------------------------------------------------

  const drawerOpen = ref(false);
  /** The row that opened the drawer — the source of the delete id + confirm token. */
  const selectedSecret = ref<ColonelSecret | null>(null);

  const receiptUrl = (): string =>
    `/api/colonel/secrets/${encodeURIComponent(selectedSecret.value?.secret_id ?? '')}`;

  const {
    data: receiptData,
    loading: receiptLoading,
    error: receiptError,
    validationError: receiptValidationError,
    notFound: receiptNotFound,
    load: loadReceipt,
  } = useResourceFetch({
    url: receiptUrl,
    schema: colonelSecretReceiptResponseSchema,
    context: 'ColonelSecretReceiptResponse',
  });

  const receiptRecord = computed(() => receiptData.value?.record ?? null);
  const receiptDetails = computed(() => receiptData.value?.details ?? null);

  /** A non-404 network/HTTP failure, or a Zod contract mismatch. */
  const receiptLoadFailed = computed(
    () =>
      (receiptError.value !== null && !receiptNotFound.value) ||
      receiptValidationError.value !== null
  );

  function openReceipt(row: ColonelSecret): void {
    selectedSecret.value = row;
    resetDelete();
    drawerOpen.value = true;
    loadReceipt().catch(() => {});
  }

  function closeDrawer(): void {
    drawerOpen.value = false;
    selectedSecret.value = null;
  }

  const drawerSubtitle = computed(() => {
    const s = selectedSecret.value;
    if (!s) return undefined;
    return stateLabel(s.state);
  });

  const yesNo = (value: boolean): string =>
    value ? t('web.admin.secrets.detail.yes') : t('web.admin.secrets.detail.no');

  /** Field rows for the secret record read-out. */
  const secretFields = computed(() => {
    const r = receiptRecord.value;
    if (!r) return [];
    return [
      { key: 'secretId', label: t('web.admin.secrets.fields.secretId'), value: r.secret_id },
      { key: 'shortId', label: t('web.admin.secrets.fields.shortId'), value: r.shortid },
      { key: 'state', label: t('web.admin.secrets.fields.state'), value: stateLabel(r.state) },
      {
        key: 'created',
        label: t('web.admin.secrets.fields.created'),
        value: formatDisplayDateTime(r.created),
      },
      {
        key: 'updated',
        label: t('web.admin.secrets.fields.updated'),
        value: r.updated
          ? formatDisplayDateTime(r.updated)
          : t('web.admin.secrets.detail.none'),
      },
      {
        key: 'expiration',
        label: t('web.admin.secrets.fields.expiration'),
        value: r.expiration
          ? formatDisplayDateTime(r.expiration)
          : t('web.admin.secrets.never'),
      },
      {
        key: 'age',
        label: t('web.admin.secrets.fields.age'),
        value: t('web.admin.secrets.ageDays', { days: ageInDays(r.age) }),
      },
      {
        key: 'lifespan',
        label: t('web.admin.secrets.fields.lifespan'),
        value: r.lifespan ?? t('web.admin.secrets.detail.none'),
      },
      {
        key: 'owner',
        label: t('web.admin.secrets.fields.owner'),
        value: ownerLabel(r.owner_id),
      },
      {
        key: 'receiptId',
        label: t('web.admin.secrets.fields.receiptId'),
        value: r.receipt_id || t('web.admin.secrets.detail.none'),
      },
      {
        key: 'hasCiphertext',
        label: t('web.admin.secrets.fields.hasCiphertext'),
        value: yesNo(r.has_ciphertext),
      },
      {
        key: 'ciphertextLength',
        label: t('web.admin.secrets.fields.ciphertextLength'),
        value: r.ciphertext_length,
      },
    ];
  });

  /** Field rows for the receipt metadata read-out (only when a receipt exists). */
  const receiptFields = computed(() => {
    const m = receiptDetails.value?.metadata;
    if (!m) return [];
    const recipients = Array.isArray(m.recipients)
      ? m.recipients.join(', ')
      : (m.recipients ?? t('web.admin.secrets.detail.none'));
    return [
      { key: 'receiptId', label: t('web.admin.secrets.receiptFields.receiptId'), value: m.receipt_id },
      { key: 'shortId', label: t('web.admin.secrets.receiptFields.shortId'), value: m.shortid },
      { key: 'state', label: t('web.admin.secrets.receiptFields.state'), value: m.state },
      {
        key: 'secretTtl',
        label: t('web.admin.secrets.receiptFields.secretTtl'),
        value: m.secret_ttl ?? t('web.admin.secrets.detail.none'),
      },
      {
        key: 'recipients',
        label: t('web.admin.secrets.receiptFields.recipients'),
        value: recipients || t('web.admin.secrets.detail.none'),
      },
      {
        key: 'hasPassphrase',
        label: t('web.admin.secrets.receiptFields.hasPassphrase'),
        value: yesNo(m.has_passphrase),
      },
      {
        key: 'shareDomain',
        label: t('web.admin.secrets.receiptFields.shareDomain'),
        value: m.share_domain || t('web.admin.secrets.detail.none'),
      },
      {
        key: 'created',
        label: t('web.admin.secrets.receiptFields.created'),
        value: formatDisplayDateTime(m.created),
      },
      {
        key: 'secretExpired',
        label: t('web.admin.secrets.receiptFields.secretExpired'),
        value: yesNo(m.secret_expired),
      },
    ];
  });

  /** Owner read-out rows (only when the secret has a non-anonymous owner). */
  const ownerFields = computed(() => {
    const o = receiptDetails.value?.owner;
    if (!o) return [];
    return [
      { key: 'email', label: t('web.admin.secrets.ownerFields.email'), value: o.email },
      { key: 'userId', label: t('web.admin.secrets.ownerFields.userId'), value: o.user_id },
      { key: 'role', label: t('web.admin.secrets.ownerFields.role'), value: o.role },
      {
        key: 'verified',
        label: t('web.admin.secrets.ownerFields.verified'),
        value: yesNo(o.verified),
      },
    ];
  });

  /** Human label for an owner id ('anon'/empty → Anonymous). */
  function ownerLabel(ownerId: string | null): string {
    if (!ownerId || ownerId === 'anon') return t('web.admin.secrets.anonymous');
    return ownerId;
  }

  // ---- Guarded delete (D4) --------------------------------------------------

  const deleteDialogOpen = ref(false);

  const {
    loading: deleteLoading,
    error: deleteError,
    run: runDelete,
    reset: resetDelete,
  } = useAdminMutation(async () => {
    const secretId = selectedSecret.value?.secret_id;
    if (!secretId) throw new Error('No secret selected');
    const response = await $api.delete(
      `/api/colonel/secrets/${encodeURIComponent(secretId)}`
    );
    // A 2xx means the secret was deleted server-side regardless of ack shape; the
    // parse keeps the contract a live tripwire without failing the action.
    gracefulParse(
      colonelSecretDeleteResponseSchema,
      response.data,
      'ColonelSecretDeleteResponse'
    );
  });

  /** The exact string the operator must retype to enable the delete. */
  const deleteToken = computed(() => selectedSecret.value?.shortid ?? '');

  function requestDelete(): void {
    resetDelete();
    deleteDialogOpen.value = true;
  }

  async function onDeleteConfirm(): Promise<void> {
    const ok = await runDelete();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    deleteDialogOpen.value = false;
    closeDrawer();
    notifications.show(t('web.admin.secrets.actions.delete.success'), 'success');
    // The deleted row is gone — refresh the current page.
    await fetchPage(pagination.value?.page ?? 1);
  }

  function onDeleteCancel(): void {
    deleteDialogOpen.value = false;
    resetDelete();
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.secrets.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.secrets.description') }}
      </p>
    </div>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="secrets-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.secrets.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.secrets.list.retry') }}
      </button>
    </div>

    <!-- Table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="secrets"
        row-key="secret_id"
        :loading="loading"
        :empty-text="t('web.admin.secrets.list.empty')"
        clickable-rows
        testid="secrets-table"
        @row-click="openReceipt">
        <template #cell-shortid="{ row }">
          <span class="font-mono text-gray-900 dark:text-white">{{ row.shortid }}</span>
        </template>

        <template #cell-state="{ row }">
          <span
            class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
            :class="stateBadgeClass(row.state)">
            {{ stateLabel(row.state) }}
          </span>
        </template>

        <template #cell-owner="{ row }">
          <span class="text-gray-600 dark:text-gray-400">{{ ownerLabel(row.owner_id) }}</span>
        </template>

        <template #cell-created="{ row }">
          {{ formatDisplayDateTime(row.created) }}
        </template>

        <template #cell-expiration="{ row }">
          {{ row.expiration ? formatDisplayDateTime(row.expiration) : t('web.admin.secrets.never') }}
        </template>

        <template #cell-age="{ row }">
          {{ ageInDays(row.age) }}
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

    <!-- Receipt drawer -->
    <DetailDrawer
      v-model:open="drawerOpen"
      :title="selectedSecret ? t('web.admin.secrets.drawer.title', { shortid: selectedSecret.shortid }) : ''"
      :subtitle="drawerSubtitle"
      width-class="max-w-lg"
      testid="secret-drawer"
      @close="closeDrawer">
      <!-- Loading -->
      <div
        v-if="receiptLoading && !receiptRecord"
        class="flex items-center justify-center py-16 text-gray-500 dark:text-gray-400"
        data-testid="secret-drawer-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="6"
          class="animate-spin motion-reduce:animate-none" />
        <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
      </div>

      <!-- Not found -->
      <div
        v-else-if="receiptNotFound"
        class="px-2 py-12 text-center"
        data-testid="secret-drawer-not-found">
        <OIcon
          collection="heroicons"
          name="key"
          size="8"
          class="mx-auto text-gray-400 dark:text-gray-600" />
        <h3 class="mt-3 text-base font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.secrets.drawer.notFound') }}
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.secrets.drawer.notFoundDescription') }}
        </p>
      </div>

      <!-- Load error -->
      <div
        v-else-if="receiptLoadFailed"
        class="px-2 py-12 text-center"
        role="alert"
        data-testid="secret-drawer-error">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="8"
          class="mx-auto text-red-500 dark:text-red-400" />
        <p class="mt-3 text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.secrets.drawer.loadError') }}
        </p>
        <button
          type="button"
          class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadReceipt().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.secrets.drawer.retry') }}
        </button>
      </div>

      <!-- Loaded -->
      <div
        v-else-if="receiptRecord"
        class="space-y-6"
        data-testid="secret-drawer-content">
        <!-- Secret record -->
        <section>
          <h3 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.sections.secret') }}
          </h3>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in secretFields"
              :key="field.key"
              :data-testid="`secret-field-${field.key}`">
              <dt class="text-xs font-medium text-gray-500 dark:text-gray-400">{{ field.label }}</dt>
              <dd class="mt-0.5 break-words font-mono text-sm text-gray-900 dark:text-gray-100">
                {{ field.value }}
              </dd>
            </div>
          </dl>
        </section>

        <!-- Receipt metadata -->
        <section data-testid="secret-drawer-receipt">
          <h3 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.sections.receipt') }}
          </h3>
          <dl
            v-if="receiptDetails?.metadata"
            class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in receiptFields"
              :key="field.key"
              :data-testid="`receipt-field-${field.key}`">
              <dt class="text-xs font-medium text-gray-500 dark:text-gray-400">{{ field.label }}</dt>
              <dd class="mt-0.5 break-words font-mono text-sm text-gray-900 dark:text-gray-100">
                {{ field.value }}
              </dd>
            </div>
          </dl>
          <p
            v-else
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.receipt.none') }}
          </p>
        </section>

        <!-- Owner -->
        <section data-testid="secret-drawer-owner">
          <h3 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.sections.owner') }}
          </h3>
          <dl
            v-if="receiptDetails?.owner"
            class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in ownerFields"
              :key="field.key"
              :data-testid="`owner-field-${field.key}`">
              <dt class="text-xs font-medium text-gray-500 dark:text-gray-400">{{ field.label }}</dt>
              <dd class="mt-0.5 break-words text-sm text-gray-900 dark:text-gray-100">
                {{ field.value }}
              </dd>
            </div>
          </dl>
          <p
            v-else
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.owner.anonymous') }}
          </p>
        </section>

        <!-- Raw inspector -->
        <section>
          <h3 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.sections.raw') }}
          </h3>
          <JsonViewer
            :data="receiptData"
            :expand-depth="2"
            testid="secret-drawer-json" />
        </section>
      </div>

      <!-- Footer: guarded delete -->
      <template #footer>
        <button
          type="button"
          data-testid="secret-delete-button"
          :disabled="!selectedSecret"
          class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
          @click="requestDelete">
          <OIcon
            collection="heroicons"
            name="trash"
            size="4" />
          {{ t('web.admin.secrets.actions.delete.button') }}
        </button>
      </template>
    </DetailDrawer>

    <!-- Typed-confirmation delete gate (danger). -->
    <AdminConfirmDialog
      v-model:open="deleteDialogOpen"
      :title="t('web.admin.secrets.actions.delete.confirmTitle')"
      :description="t('web.admin.secrets.actions.delete.confirmDescription', { shortid: deleteToken })"
      :confirm-token="deleteToken"
      variant="danger"
      :confirm-text="t('web.admin.secrets.actions.delete.button')"
      :loading="deleteLoading"
      :error="deleteError"
      @confirm="onDeleteConfirm"
      @cancel="onDeleteCancel" />
  </div>
</template>
