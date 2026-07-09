<!-- src/apps/admin/views/AdminSecrets.vue -->

<script setup lang="ts">
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { AdminConfirmDialog, JsonViewer } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
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
   * Secrets screen (ticket #30) — LOOKUP-FIRST by design review: on a
   * zero-knowledge platform there is nothing to gain from browsing every
   * secret, so the paginated browse-all table was removed (the list endpoint
   * still exists server-side; this screen never calls it).
   *
   * - LOOKUP: the operator pastes a secret's key (identifier); the screen loads
   *   GET /api/colonel/secrets/:secret_id via {@link useResourceFetch} and
   *   renders the same inspect read-out the old receipt drawer showed (secret
   *   record + receipt metadata + owner + raw JSON inspector).
   * - GUARDED DELETE (D4): the destructive delete that
   *   `DELETE /api/colonel/secrets/:secret_id` has always supported, gated by
   *   {@link AdminConfirmDialog} typed-confirmation (retype the secret's short
   *   id) in danger mode. On success the read-out clears.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  // ---- Lookup ---------------------------------------------------------------

  /** The input value (a secret's full key / identifier, not its short id). */
  const secretKey = ref('');
  /** The key actually fetched — the URL + delete target read this, never the input. */
  const lookedUpKey = ref('');

  const keyReady = computed(() => secretKey.value.trim() !== '');

  const receiptUrl = (): string =>
    `/api/colonel/secrets/${encodeURIComponent(lookedUpKey.value)}`;

  const {
    data: receiptData,
    loading: receiptLoading,
    error: receiptError,
    validationError: receiptValidationError,
    notFound: receiptNotFound,
    load: loadReceipt,
    reset: resetReceipt,
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

  function onLookup(): void {
    const key = secretKey.value.trim();
    if (!key) return;
    lookedUpKey.value = key;
    resetDelete();
    loadReceipt().catch(() => {
      // Failure state is captured by the composable (`notFound` / `error`);
      // the panels below render it. Swallow so it doesn't become unhandled.
    });
  }

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
    const secretId = receiptRecord.value?.secret_id;
    if (!secretId) throw new Error('No secret loaded');
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
  const deleteToken = computed(() => receiptRecord.value?.shortid ?? '');

  function requestDelete(): void {
    resetDelete();
    deleteDialogOpen.value = true;
  }

  async function onDeleteConfirm(): Promise<void> {
    const ok = await runDelete();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    deleteDialogOpen.value = false;
    notifications.show(t('web.admin.secrets.actions.delete.success'), 'success');
    // The secret is gone — clear the read-out back to the lookup prompt.
    resetReceipt();
    lookedUpKey.value = '';
    secretKey.value = '';
  }

  function onDeleteCancel(): void {
    deleteDialogOpen.value = false;
    resetDelete();
  }
</script>

<template>
  <div class="mx-auto max-w-4xl space-y-8">
    <!-- Page header -->
    <div>
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.secrets.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.secrets.description') }}
      </p>
    </div>

    <!-- Lookup -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <form
        class="flex flex-wrap items-end gap-3"
        data-testid="secret-lookup-form"
        @submit.prevent="onLookup">
        <div class="min-w-[18rem] flex-1">
          <label
            for="secret-key-input"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.secrets.lookup.label') }}
          </label>
          <input
            id="secret-key-input"
            v-model="secretKey"
            type="text"
            autocomplete="off"
            spellcheck="false"
            data-testid="secret-lookup-input"
            :placeholder="t('web.admin.secrets.lookup.placeholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="submit"
          data-testid="secret-lookup-submit"
          :disabled="!keyReady || receiptLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50">
          <OIcon
            collection="heroicons"
            :name="receiptLoading ? 'arrow-path' : 'magnifying-glass'"
            size="4"
            :class="receiptLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
          {{ t('web.admin.secrets.lookup.button') }}
        </button>
      </form>
    </section>

    <!-- Loading -->
    <div
      v-if="receiptLoading && !receiptRecord"
      class="flex items-center justify-center py-16 text-gray-500 dark:text-gray-400"
      data-testid="secret-lookup-loading">
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
      class="rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="secret-lookup-not-found">
      <OIcon
        collection="heroicons"
        name="key"
        size="8"
        class="mx-auto text-gray-400 dark:text-gray-600" />
      <h3 class="mt-3 text-base font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.secrets.lookup.notFound') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.secrets.lookup.notFoundDescription') }}
      </p>
    </div>

    <!-- Load error -->
    <div
      v-else-if="receiptLoadFailed"
      class="rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm dark:border-gray-800 dark:bg-gray-900"
      role="alert"
      data-testid="secret-lookup-error">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        size="8"
        class="mx-auto text-red-500 dark:text-red-400" />
      <p class="mt-3 text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.secrets.lookup.loadError') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="loadReceipt().catch(() => {})">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.secrets.lookup.retry') }}
      </button>
    </div>

    <!-- Loaded read-out (the old drawer content, inline) -->
    <div
      v-else-if="receiptRecord"
      class="space-y-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="secret-lookup-result">
      <div class="flex items-center gap-3">
        <h3 class="font-mono text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.admin.secrets.lookup.resultTitle', { shortid: receiptRecord.shortid }) }}
        </h3>
        <span
          class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
          :class="stateBadgeClass(receiptRecord.state)">
          {{ stateLabel(receiptRecord.state) }}
        </span>
      </div>

      <!-- Secret record -->
      <section>
        <h4 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {{ t('web.admin.secrets.sections.secret') }}
        </h4>
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
      <section data-testid="secret-result-receipt">
        <h4 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {{ t('web.admin.secrets.sections.receipt') }}
        </h4>
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
      <section data-testid="secret-result-owner">
        <h4 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {{ t('web.admin.secrets.sections.owner') }}
        </h4>
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
        <h4 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {{ t('web.admin.secrets.sections.raw') }}
        </h4>
        <JsonViewer
          :data="receiptData"
          :expand-depth="2"
          testid="secret-result-json" />
      </section>

      <!-- Guarded delete -->
      <div class="border-t border-gray-100 pt-4 dark:border-gray-800">
        <button
          type="button"
          data-testid="secret-delete-button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
          @click="requestDelete">
          <OIcon
            collection="heroicons"
            name="trash"
            size="4" />
          {{ t('web.admin.secrets.actions.delete.button') }}
        </button>
      </div>
    </div>

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
