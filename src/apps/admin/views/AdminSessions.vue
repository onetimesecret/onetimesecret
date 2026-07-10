<!-- src/apps/admin/views/AdminSessions.vue -->

<script setup lang="ts">

  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import {
    AdminConfirmDialog,
    DataTable,
    DetailDrawer,
    FilterBar,
    JsonViewer,
    KitPagination,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { useAdminSessions } from '@/apps/admin/stores/useAdminSessions';
  import type { ColonelSession } from '@/schemas/api/internal/responses/colonel-sessions';
  import {
    colonelSessionDetailResponseSchema,
    colonelSessionDeleteResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-sessions';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Sessions console (ticket #40) — the first Phase-3 screen: a CLI-only power
   * (`bin/ots session …`) surfaced in the browser for incident response, built
   * fresh on the Slice-3 template (no `src/apps/colonel/*` / `colonelInfoStore`).
   *
   * - LIST + SEARCH: DataTable + FilterBar + KitPagination over the NEW
   *   {@link useAdminSessions} store. The `GET /api/colonel/sessions` endpoint is
   *   a thin adapter over `Onetime::Operations::Sessions::List` (bounded scan,
   *   #2211) and supports a server-side `search` filter (email / external id).
   * - DETAIL DRAWER: a row opens {@link DetailDrawer} loading
   *   `GET /api/colonel/sessions/:session_id` via {@link useResourceFetch}
   *   (`Sessions::Inspect`) — typed field read-out + raw JSON inspector.
   * - GUARDED REVOKE (D4): revoking a session logs that user out mid-flight, so it
   *   is gated by {@link AdminConfirmDialog} typed-confirmation (retype the session
   *   id) in danger mode and audited SERVER-SIDE by `Sessions::Delete`. It can be
   *   triggered from the row action or the drawer footer.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const store = useAdminSessions();
  const { sessions, pagination, loading, error } = storeToRefs(store);

  // ---- List + search --------------------------------------------------------

  const searchTerm = ref('');
  const activeSearch = ref('');
  const hasActiveFilters = computed(() => searchTerm.value !== '');

  const columns = computed<DataTableColumn<ColonelSession>[]>(() => [
    { key: 'session_id', label: t('web.admin.sessions.columns.sessionId') },
    { key: 'authenticated', label: t('web.admin.sessions.columns.authenticated'), align: 'center' },
    { key: 'email', label: t('web.admin.sessions.columns.email') },
    { key: 'external_id', label: t('web.admin.sessions.columns.externalId') },
    { key: 'ip_address', label: t('web.admin.sessions.columns.ipAddress') },
    { key: 'created_at', label: t('web.admin.sessions.columns.created') },
    { key: 'actions', label: t('web.admin.sessions.columns.actions'), align: 'right' },
  ]);

  /** created_at is a bare Unix-second number (authenticated_at). */
  function createdLabel(createdAt: number | null): string {
    if (!createdAt) return t('web.admin.sessions.detail.unknown');
    return formatDisplayDateTime(new Date(createdAt * 1000));
  }

  function emailLabel(email: string | null): string {
    return email || t('web.admin.sessions.anonymous');
  }

  /** Fetch one server page with the active search term. Errors surface via the store. */
  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage, activeSearch.value || undefined);
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow so it doesn't become unhandled.
    }
  }

  // Debounce search input so we issue one request per pause, not per keystroke.
  let searchTimer: ReturnType<typeof setTimeout> | null = null;
  watch(searchTerm, (value) => {
    if (searchTimer) clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      activeSearch.value = value.trim();
      fetchPage(1);
    }, 300);
  });
  onBeforeUnmount(() => {
    if (searchTimer) clearTimeout(searchTimer);
  });

  function onClear(): void {
    searchTerm.value = '';
    activeSearch.value = '';
    fetchPage(1);
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Detail drawer (inspect) ----------------------------------------------

  const drawerOpen = ref(false);
  /** The row that opened the drawer — the source of the detail id. */
  const selectedSession = ref<ColonelSession | null>(null);

  const detailUrl = (): string =>
    `/api/colonel/sessions/${encodeURIComponent(selectedSession.value?.session_id ?? '')}`;

  const {
    data: detailData,
    loading: detailLoading,
    error: detailError,
    validationError: detailValidationError,
    notFound: detailNotFound,
    load: loadDetail,
  } = useResourceFetch({
    url: detailUrl,
    schema: colonelSessionDetailResponseSchema,
    context: 'ColonelSessionDetailResponse',
  });

  const detailRecord = computed(() => detailData.value?.record ?? null);

  /** A non-404 network/HTTP failure, or a Zod contract mismatch. */
  const detailLoadFailed = computed(
    () =>
      (detailError.value !== null && !detailNotFound.value) ||
      detailValidationError.value !== null
  );

  function openDetail(row: ColonelSession): void {
    selectedSession.value = row;
    resetRevoke();
    drawerOpen.value = true;
    loadDetail().catch(() => {});
  }

  function closeDrawer(): void {
    drawerOpen.value = false;
    selectedSession.value = null;
  }

  const yesNo = (value: boolean): string =>
    value ? t('web.admin.sessions.detail.yes') : t('web.admin.sessions.detail.no');

  const none = (value: unknown): string =>
    value === null || value === undefined || value === ''
      ? t('web.admin.sessions.detail.none')
      : String(value);

  /** Human TTL: -1 = no expiry, <= 0 = expired, else seconds. */
  function ttlLabel(ttl: number | null): string {
    if (ttl === null || ttl === undefined) return t('web.admin.sessions.detail.none');
    if (ttl === -1) return t('web.admin.sessions.detail.noExpiry');
    if (ttl <= 0) return t('web.admin.sessions.detail.expired');
    return t('web.admin.sessions.detail.ttlSeconds', { seconds: ttl });
  }

  /** Field rows for the session record read-out. */
  const sessionFields = computed(() => {
    const r = detailRecord.value;
    if (!r) return [];
    return [
      { key: 'sessionId', label: t('web.admin.sessions.fields.sessionId'), value: r.session_id },
      { key: 'key', label: t('web.admin.sessions.fields.key'), value: r.key },
      { key: 'ttl', label: t('web.admin.sessions.fields.ttl'), value: ttlLabel(r.ttl) },
      {
        key: 'authenticated',
        label: t('web.admin.sessions.fields.authenticated'),
        value: yesNo(r.authenticated),
      },
      { key: 'email', label: t('web.admin.sessions.fields.email'), value: none(r.email) },
      { key: 'externalId', label: t('web.admin.sessions.fields.externalId'), value: none(r.external_id) },
      { key: 'accountId', label: t('web.admin.sessions.fields.accountId'), value: none(r.account_id) },
      { key: 'role', label: t('web.admin.sessions.fields.role'), value: none(r.role) },
      { key: 'locale', label: t('web.admin.sessions.fields.locale'), value: none(r.locale) },
      { key: 'ipAddress', label: t('web.admin.sessions.fields.ipAddress'), value: none(r.ip_address) },
      {
        key: 'authenticatedAt',
        label: t('web.admin.sessions.fields.authenticatedAt'),
        value: r.authenticated_at
          ? formatDisplayDateTime(new Date(r.authenticated_at * 1000))
          : t('web.admin.sessions.detail.none'),
      },
      {
        key: 'authenticatedBy',
        label: t('web.admin.sessions.fields.authenticatedBy'),
        value: none(r.authenticated_by),
      },
      {
        key: 'activeSessionId',
        label: t('web.admin.sessions.fields.activeSessionId'),
        value: none(r.active_session_id),
      },
    ];
  });

  // ---- Guarded revoke (D4) --------------------------------------------------

  const revokeDialogOpen = ref(false);
  /** The session id the confirm dialog is gating (retype token + request target). */
  const revokeTarget = ref('');

  const {
    loading: revokeLoading,
    error: revokeError,
    run: runRevoke,
    reset: resetRevoke,
  } = useAdminMutation(async () => {
    const sessionId = revokeTarget.value;
    if (!sessionId) throw new Error('No session selected');
    const response = await $api.delete(
      `/api/colonel/sessions/${encodeURIComponent(sessionId)}`
    );
    // A 2xx means the session was revoked server-side regardless of ack shape;
    // the parse keeps the contract a live tripwire without failing the action.
    gracefulParse(
      colonelSessionDeleteResponseSchema,
      response.data,
      'ColonelSessionDeleteResponse'
    );
  });

  function requestRevoke(sessionId: string): void {
    revokeTarget.value = sessionId;
    resetRevoke();
    revokeDialogOpen.value = true;
  }

  async function onRevokeConfirm(): Promise<void> {
    const revokedId = revokeTarget.value;
    const ok = await runRevoke();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    revokeDialogOpen.value = false;
    notifications.show(t('web.admin.sessions.revoke.success'), 'success');

    // If the revoked session is the one open in the drawer, close it.
    if (selectedSession.value?.session_id === revokedId) {
      closeDrawer();
    }
    // The revoked row is gone — refresh the current page.
    await fetchPage(pagination.value?.page ?? 1);
  }

  function onRevokeCancel(): void {
    revokeDialogOpen.value = false;
    resetRevoke();
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.sessions.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.sessions.description') }}
      </p>
    </header>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="sessions-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.sessions.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.sessions.list.retry') }}
      </button>
    </div>

    <!-- Search -->
    <div class="mb-4">
      <FilterBar
        v-model:search="searchTerm"
        :search-placeholder="t('web.admin.sessions.search.placeholder')"
        :has-active-filters="hasActiveFilters"
        testid="sessions-filterbar"
        @clear="onClear" />
    </div>

    <!-- Table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="sessions"
        row-key="session_id"
        :loading="loading"
        :empty-text="t('web.admin.sessions.list.empty')"
        clickable-rows
        testid="sessions-table"
        @row-click="openDetail">
        <template #cell-session_id="{ row }">
          <span class="font-mono text-gray-900 dark:text-white">{{ row.session_id }}</span>
        </template>

        <template #cell-authenticated="{ row }">
          <OIcon
            v-if="row.authenticated"
            collection="heroicons"
            name="check-circle"
            size="5"
            class="inline text-green-600 dark:text-green-400"
            :aria-label="t('web.admin.sessions.status.authenticated')" />
          <span
            v-else
            class="text-gray-400 dark:text-gray-600"
            :aria-label="t('web.admin.sessions.status.anonymous')">—</span>
        </template>

        <template #cell-email="{ row }">
          <span class="text-gray-900 dark:text-white">
            <RevealEmail
              v-if="row.email"
              :email="row.email" />
            <template v-else>{{ emailLabel(row.email) }}</template>
          </span>
        </template>

        <template #cell-external_id="{ row }">
          <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{ row.external_id || '—' }}</span>
        </template>

        <template #cell-ip_address="{ row }">
          <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{ row.ip_address || '—' }}</span>
        </template>

        <template #cell-created_at="{ row }">
          {{ createdLabel(row.created_at) }}
        </template>

        <template #cell-actions="{ row }">
          <button
            type="button"
            :data-testid="`revoke-${row.session_id}`"
            class="text-sm font-medium text-red-600 hover:text-red-800 focus:ring-2 focus:ring-red-500 focus:outline-none dark:text-red-400 dark:hover:text-red-300"
            @click.stop="requestRevoke(row.session_id)">
            {{ t('web.admin.sessions.revoke.button') }}
          </button>
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

    <!-- Detail drawer (inspect) -->
    <DetailDrawer
      v-model:open="drawerOpen"
      :title="selectedSession ? t('web.admin.sessions.drawer.title', { id: selectedSession.session_id }) : ''"
      :subtitle="selectedSession ? emailLabel(selectedSession.email) : undefined"
      width-class="max-w-lg"
      testid="session-drawer"
      @close="closeDrawer">
      <!-- Loading -->
      <div
        v-if="detailLoading && !detailRecord"
        class="flex items-center justify-center py-16 text-gray-500 dark:text-gray-400"
        data-testid="session-drawer-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="6"
          class="animate-spin motion-reduce:animate-none" />
        <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
      </div>

      <!-- Not found -->
      <div
        v-else-if="detailNotFound"
        class="px-2 py-12 text-center"
        data-testid="session-drawer-not-found">
        <OIcon
          collection="heroicons"
          name="finger-print"
          size="8"
          class="mx-auto text-gray-400 dark:text-gray-600" />
        <h3 class="mt-3 text-base font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.sessions.drawer.notFound') }}
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.sessions.drawer.notFoundDescription') }}
        </p>
      </div>

      <!-- Load error -->
      <div
        v-else-if="detailLoadFailed"
        class="px-2 py-12 text-center"
        role="alert"
        data-testid="session-drawer-error">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="8"
          class="mx-auto text-red-500 dark:text-red-400" />
        <p class="mt-3 text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.sessions.drawer.loadError') }}
        </p>
        <button
          type="button"
          class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadDetail().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.sessions.drawer.retry') }}
        </button>
      </div>

      <!-- Loaded -->
      <div
        v-else-if="detailRecord"
        class="space-y-6"
        data-testid="session-drawer-content">
        <!-- Session record -->
        <section>
          <h3 class="mb-2 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.sessions.sections.session') }}
          </h3>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in sessionFields"
              :key="field.key"
              :data-testid="`session-field-${field.key}`">
              <dt class="text-xs font-medium text-gray-500 dark:text-gray-400">
                {{ field.label }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-words text-gray-900 dark:text-gray-100">
                <RevealEmail
                  v-if="field.key === 'email' && selectedSession?.email"
                  :email="selectedSession.email" />
                <template v-else>{{ field.value }}</template>
              </dd>
            </div>
          </dl>
        </section>

        <!-- Raw inspector -->
        <section>
          <h3 class="mb-2 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.sessions.sections.raw') }}
          </h3>
          <JsonViewer
            :data="detailData?.details?.data"
            :expand-depth="1"
            testid="session-drawer-json" />
        </section>
      </div>

      <!-- Footer: guarded revoke -->
      <template #footer>
        <button
          type="button"
          data-testid="session-revoke-button"
          :disabled="!selectedSession"
          class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
          @click="selectedSession && requestRevoke(selectedSession.session_id)">
          <OIcon
            collection="heroicons"
            name="trash"
            size="4" />
          {{ t('web.admin.sessions.revoke.button') }}
        </button>
      </template>
    </DetailDrawer>

    <!-- Typed-confirmation revoke gate (danger). -->
    <AdminConfirmDialog
      v-model:open="revokeDialogOpen"
      :title="t('web.admin.sessions.revoke.confirmTitle')"
      :description="t('web.admin.sessions.revoke.confirmDescription', { id: revokeTarget })"
      :confirm-token="revokeTarget"
      variant="danger"
      :confirm-text="t('web.admin.sessions.revoke.button')"
      :loading="revokeLoading"
      :error="revokeError"
      @confirm="onRevokeConfirm"
      @cancel="onRevokeCancel" />
  </div>
</template>
