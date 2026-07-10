<!-- src/apps/admin/components/EmailDeliverabilitySection.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import {
    AdminConfirmDialog,
    DataTable,
    KitPagination,
    StatCard,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type {
    ColonelDeliverabilityEvent,
    ColonelEmailMessage,
    ColonelEmailSuppression,
  } from '@/schemas/api/internal/responses/colonel-deliverability';
  import {
    colonelEmailDeliverabilityEventsResponseSchema,
    colonelEmailDeliverabilityResponseSchema,
    colonelEmailMessagesResponseSchema,
    colonelEmailRecipientLookupResponseSchema,
    colonelEmailSuppressionAddResponseSchema,
    colonelEmailSuppressionRemoveResponseSchema,
    colonelEmailSuppressionsResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-deliverability';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Deliverability section for the Email Tools screen — the RECEIVING side of
   * email. The screen's other sections prove mail goes OUT (template preview,
   * test send); this one shows what comes BACK: bounce/complaint counts, the
   * suppression list the outbound guard skips, and the raw event feed — the
   * data that diagnoses a sender-reputation problem.
   *
   * Three sub-blocks, all under the `emailtools.deliverability` namespace:
   *  - SUMMARY TILES (read-only): suppressed total, bounces/complaints inside
   *    the server's recent window, and sends the suppression guard skipped.
   *  - SUPPRESSION LIST: newest-first pages plus an EXACT-address lookup (the
   *    store is keyed by address — a substring search would imply a capability
   *    the endpoint lacks). Removal is GUARDED (one-click confirm, the unban
   *    idiom): it re-enables sending to an address that bounced or complained,
   *    and is audited SERVER-SIDE by the op (CONTRACT 4).
   *  - RECENT EVENTS (read-only): the newest slice of the bounce/complaint
   *    feed. Its empty state explains how feedback gets here: an operator
   *    relay POSTs ESP records to the colonel-authenticated ingest endpoint
   *    (no public webhook, by design).
   *
   * Every mutation goes through {@link useAdminMutation}; nothing here logs.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const SUMMARY_URL = '/api/colonel/email/deliverability';
  const SUPPRESSIONS_URL = '/api/colonel/email/deliverability/suppressions';
  const EVENTS_URL = '/api/colonel/email/deliverability/events';
  // Track B — live provider reads of the ACTIVE transport (Mailer.determine_provider).
  const LOOKUP_URL = '/api/colonel/email/deliverability/lookup';
  const MESSAGES_URL = '/api/colonel/email/deliverability/messages';

  /** The "recent" feed shows one newest-first slice (the API also paginates). */
  const EVENTS_LIMIT = 20;
  /** Item-9 send log slice size (Lettermint is cursor-paginated). */
  const MESSAGES_LIMIT = 30;

  // ---- Summary tiles ---------------------------------------------------------

  const {
    data: summaryData,
    loading: summaryLoading,
    error: summaryError,
    load: loadSummary,
  } = useResourceFetch({
    url: SUMMARY_URL,
    schema: colonelEmailDeliverabilityResponseSchema,
    context: 'ColonelEmailDeliverabilityResponse',
  });

  const counts = computed(() => summaryData.value?.details?.counts ?? null);
  const windowDays = computed(() => summaryData.value?.details?.window_days ?? 7);

  // ---- Sync status (ITEM 2, read-only) --------------------------------------
  // Per-provider last-sync feed from the SAME summary fetch. Backend always
  // emits `{}` when nothing has ever synced → empty OR undefined = never synced.

  const syncStatus = computed(() => summaryData.value?.details?.sync_status ?? {});
  const syncEntries = computed(() =>
    Object.entries(syncStatus.value).map(([provider, status]) => ({ provider, ...status }))
  );
  const neverSynced = computed(() => syncEntries.value.length === 0);

  function reloadSummary(): void {
    loadSummary().catch(() => {}); // summaryError drives the inline alert
  }

  // ---- Suppression list (paginated + exact-address lookup) -------------------

  const suppressions = ref<ColonelEmailSuppression[]>([]);
  const suppressionsMeta = ref<PageMeta | null>(null);
  const searchTerm = ref('');
  /** The lookup actually applied to the current rows (submitted, not typed). */
  const activeSearch = ref('');

  const {
    loading: suppressionsLoading,
    error: suppressionsError,
    perPage: suppressionsPerPage,
    fetchPage: fetchSuppressionsPage,
  } = usePaginatedFetch({
    url: SUPPRESSIONS_URL,
    schema: colonelEmailSuppressionsResponseSchema,
    context: 'ColonelEmailSuppressionsResponse',
    select: (data) => ({
      items: data.details?.suppressions ?? [],
      pagination: data.details?.pagination ?? null,
    }),
    perPage: 25,
  });

  async function fetchSuppressions(targetPage = 1): Promise<void> {
    try {
      const result = await fetchSuppressionsPage(
        targetPage,
        activeSearch.value ? { search: activeSearch.value } : undefined
      );
      if (result) {
        suppressions.value = result.items;
        suppressionsMeta.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty (gracefulParse already reported).
        suppressions.value = [];
        suppressionsMeta.value = null;
      }
    } catch {
      // suppressionsError drives the banner; keep stale rows off the screen.
      suppressions.value = [];
      suppressionsMeta.value = null;
    }
  }

  function onSearchSubmit(): void {
    activeSearch.value = searchTerm.value.trim();
    fetchSuppressions(1);
  }

  function onSearchClear(): void {
    searchTerm.value = '';
    activeSearch.value = '';
    fetchSuppressions(1);
  }

  function onSuppressionsPerPage(perPage: number): void {
    suppressionsPerPage.value = perPage;
    fetchSuppressions(1);
  }

  const suppressionColumns = computed<DataTableColumn<ColonelEmailSuppression>[]>(() => [
    { key: 'address', label: t('web.admin.emailtools.deliverability.suppressions.columns.address') },
    { key: 'reason', label: t('web.admin.emailtools.deliverability.suppressions.columns.reason') },
    { key: 'source', label: t('web.admin.emailtools.deliverability.suppressions.columns.source') },
    { key: 'created', label: t('web.admin.emailtools.deliverability.suppressions.columns.added') },
    {
      key: 'actions',
      label: t('web.admin.emailtools.deliverability.suppressions.columns.actions'),
      align: 'right',
    },
  ]);

  const suppressionsEmptyText = computed(() =>
    activeSearch.value
      ? t('web.admin.emailtools.deliverability.suppressions.emptySearch', {
          address: activeSearch.value,
        })
      : t('web.admin.emailtools.deliverability.suppressions.empty')
  );

  // ---- Guarded remove (one-click confirm — the unban idiom) ------------------

  const removeDialogOpen = ref(false);
  const removeTarget = ref('');

  const {
    loading: removeLoading,
    error: removeError,
    run: runRemove,
    reset: resetRemove,
  } = useAdminMutation(async () => {
    const response = await $api.delete(
      `${SUPPRESSIONS_URL}/${encodeURIComponent(removeTarget.value)}`
    );
    // 2xx means the suppression was removed server-side regardless of ack
    // shape; the parse keeps the contract a live tripwire, never fatal.
    gracefulParse(
      colonelEmailSuppressionRemoveResponseSchema,
      response.data,
      'ColonelEmailSuppressionRemoveResponse'
    );
  });

  function requestRemove(address: string): void {
    removeTarget.value = address;
    resetRemove();
    removeDialogOpen.value = true;
  }

  async function onRemoveConfirm(): Promise<void> {
    const ok = await runRemove();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    removeDialogOpen.value = false;
    notifications.show(
      t('web.admin.emailtools.deliverability.suppressions.remove.success', {
        address: removeTarget.value,
      }),
      'success'
    );
    // The list AND the suppressed-total tile both changed.
    fetchSuppressions(suppressionsMeta.value?.page ?? 1);
    reloadSummary();
  }

  function onRemoveCancel(): void {
    removeDialogOpen.value = false;
    resetRemove();
  }

  // ---- Guarded manual add (ITEM 6 — additive, reversible via remove) ---------
  // The POST body carries ONLY `address`; the backend hardcodes reason='manual'
  // and source='colonel'. `record.created` picks the success message.

  const addAddress = ref('');
  const addDialogOpen = ref(false);
  const addWasCreated = ref(true);
  /** A minimal e-mail sanity check so the confirm button can't submit garbage. */
  const addAddressValid = computed(() => /.+@.+\..+/.test(addAddress.value.trim()));

  const {
    loading: addLoading,
    error: addError,
    run: runAdd,
    reset: resetAdd,
  } = useAdminMutation(async () => {
    const response = await $api.post(SUPPRESSIONS_URL, { address: addAddress.value.trim() });
    const parsed = gracefulParse(
      colonelEmailSuppressionAddResponseSchema,
      response.data,
      'ColonelEmailSuppressionAddResponse'
    );
    // 2xx means the address is suppressed regardless of ack shape; the parse
    // keeps the contract a live tripwire. `created` picks new vs. already-present.
    addWasCreated.value = parsed.ok ? parsed.data.record.created : true;
  });

  function requestAdd(): void {
    if (!addAddressValid.value) return;
    resetAdd();
    addDialogOpen.value = true;
  }

  async function onAddConfirm(): Promise<void> {
    const ok = await runAdd();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    addDialogOpen.value = false;
    notifications.show(
      t(
        addWasCreated.value
          ? 'web.admin.emailtools.deliverability.suppressions.add.success'
          : 'web.admin.emailtools.deliverability.suppressions.add.successExisting',
        { address: addAddress.value.trim() }
      ),
      'success'
    );
    addAddress.value = '';
    // The list AND the suppressed-total tile both changed.
    fetchSuppressions(suppressionsMeta.value?.page ?? 1);
    reloadSummary();
  }

  function onAddCancel(): void {
    addDialogOpen.value = false;
    resetAdd();
  }

  // ---- Recent events feed -----------------------------------------------------

  const {
    data: eventsData,
    loading: eventsLoading,
    error: eventsError,
    load: loadEvents,
  } = useResourceFetch({
    url: EVENTS_URL,
    schema: colonelEmailDeliverabilityEventsResponseSchema,
    context: 'ColonelEmailDeliverabilityEventsResponse',
  });

  const events = computed<ColonelDeliverabilityEvent[]>(
    () => eventsData.value?.details?.events ?? []
  );

  function reloadEvents(): void {
    loadEvents({ page: 1, per_page: EVENTS_LIMIT }).catch(() => {}); // eventsError drives the banner
  }

  const eventColumns = computed<DataTableColumn<ColonelDeliverabilityEvent>[]>(() => [
    { key: 'created', label: t('web.admin.emailtools.deliverability.events.columns.time') },
    { key: 'kind', label: t('web.admin.emailtools.deliverability.events.columns.kind') },
    { key: 'address', label: t('web.admin.emailtools.deliverability.events.columns.address') },
    { key: 'source', label: t('web.admin.emailtools.deliverability.events.columns.source') },
    { key: 'reason', label: t('web.admin.emailtools.deliverability.events.columns.reason') },
  ]);

  /**
   * Badge styling per kind/reason: complaints are the harsher signal (red),
   * bounces warn (amber), manual imports are neutral (gray).
   */
  function kindClass(kind: string): string {
    if (kind === 'complaint') {
      return 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300';
    }
    if (kind === 'bounce') {
      return 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300';
    }
    return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
  }

  function kindLabel(kind: string): string {
    return kind === 'complaint'
      ? t('web.admin.emailtools.deliverability.events.kinds.complaint')
      : t('web.admin.emailtools.deliverability.events.kinds.bounce');
  }

  // ---- Recipient lookup (item 10 — live provider read + local store) --------
  // Keys BOTH reads (local store + provider) by the SAME normalized address.
  // The local store is authoritative and always present; `provider_result` is a
  // LIVE colonel-only read (recipient PII returned here is exempt from the
  // at-rest hashing posture: it is never persisted). Submit-driven, not live.

  const lookupAddress = ref('');
  /** The address actually looked up (submitted, not typed). */
  const activeLookupAddress = ref('');

  const {
    data: lookupData,
    loading: lookupLoading,
    error: lookupNetworkError,
    load: loadLookup,
    reset: resetLookup,
  } = useResourceFetch({
    url: LOOKUP_URL,
    schema: colonelEmailRecipientLookupResponseSchema,
    context: 'ColonelEmailRecipientLookup',
  });

  const lookupResult = computed(() => lookupData.value?.details ?? null);
  const lookupProvider = computed(() => lookupResult.value?.provider ?? '');
  /** Provider block is retryable-failed on a network throw OR available=false. */
  const lookupProviderFailed = computed(
    () =>
      lookupNetworkError.value !== null ||
      (lookupResult.value?.capability === true && lookupResult.value?.available === false)
  );
  const lookupProviderUnsupported = computed(
    () => lookupResult.value !== null && lookupResult.value.capability === false
  );

  function onLookupSubmit(): void {
    const address = lookupAddress.value.trim();
    if (!address) return;
    activeLookupAddress.value = address;
    loadLookup({ address }).catch(() => {}); // lookupNetworkError drives the alert
  }

  function onLookupClear(): void {
    lookupAddress.value = '';
    activeLookupAddress.value = '';
    resetLookup();
  }

  // ---- Recent sends feed (item 9 — provider's OWN message API) --------------
  // Gated on `capability`: SES is fire-and-forget (no per-message API) → the
  // block renders a "not available on this transport" empty-state. Subjects and
  // recipient addresses returned here are a LIVE colonel-only read, never
  // persisted (exempt from the at-rest address-hashing posture).

  const {
    data: messagesData,
    loading: messagesLoading,
    error: messagesNetworkError,
    load: loadMessages,
  } = useResourceFetch({
    url: MESSAGES_URL,
    schema: colonelEmailMessagesResponseSchema,
    context: 'ColonelEmailMessages',
  });

  const messages = computed<ColonelEmailMessage[]>(
    () => messagesData.value?.details?.messages ?? []
  );
  /** Structural: does the active transport expose a send log at all? */
  const messagesCapability = computed(
    () => messagesData.value?.details?.capability ?? true
  );
  const messagesProvider = computed(() => messagesData.value?.details?.provider ?? '');
  /** Retryable failure: network throw OR a 200 payload with available=false. */
  const messagesFailed = computed(
    () =>
      messagesNetworkError.value !== null ||
      (messagesCapability.value && messagesData.value?.details?.available === false)
  );

  function reloadMessages(): void {
    loadMessages({ page: 1, per_page: MESSAGES_LIMIT }).catch(() => {}); // messagesFailed drives the alert
  }

  const messageColumns = computed<DataTableColumn<ColonelEmailMessage>[]>(() => [
    { key: 'created_at', label: t('web.admin.emailtools.deliverability.messages.col.created') },
    { key: 'status', label: t('web.admin.emailtools.deliverability.messages.col.status') },
    { key: 'subject', label: t('web.admin.emailtools.deliverability.messages.col.subject') },
    { key: 'to', label: t('web.admin.emailtools.deliverability.messages.col.to') },
  ]);

  /** Lettermint status vocabulary → badge colour (item-9 mapping, from R2). */
  const MESSAGE_STATUS_SUCCESS = ['delivered', 'opened', 'clicked'];
  const MESSAGE_STATUS_INFLIGHT = ['pending', 'queued', 'processed'];
  const MESSAGE_STATUS_FAILURE = ['hard_bounced', 'soft_bounced', 'complained', 'suppressed'];
  const MESSAGE_STATUS_VOCAB = [
    ...MESSAGE_STATUS_SUCCESS,
    ...MESSAGE_STATUS_INFLIGHT,
    ...MESSAGE_STATUS_FAILURE,
    'unsubscribed',
  ];

  function messageStatusClass(status: string): string {
    if (MESSAGE_STATUS_SUCCESS.includes(status)) {
      return 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300';
    }
    if (MESSAGE_STATUS_FAILURE.includes(status)) {
      return 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300';
    }
    // In-flight and unsubscribed are informational (neutral gray).
    return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
  }

  function messageStatusLabel(status: string): string {
    return MESSAGE_STATUS_VOCAB.includes(status)
      ? t(`web.admin.emailtools.deliverability.messages.status.${status}`)
      : status;
  }

  onMounted(() => {
    reloadSummary();
    fetchSuppressions(1);
    reloadEvents();
    reloadMessages();
  });
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="deliverability-section">
    <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
      {{ t('web.admin.emailtools.deliverability.title') }}
    </h3>
    <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.admin.emailtools.deliverability.description') }}
    </p>

    <!-- Summary error (tiles degrade to skeletons/dashes, alert offers retry) -->
    <div
      v-if="summaryError"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="deliverability-summary-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.emailtools.deliverability.summary.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="reloadSummary">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.emailtools.deliverability.retry') }}
      </button>
    </div>

    <!-- Summary tiles -->
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.suppressed')"
        :value="counts?.suppressed_total ?? '—'"
        icon="no-symbol"
        :loading="summaryLoading"
        testid="deliverability-stat-suppressed" />
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.bounces', { days: windowDays })"
        :value="counts?.recent_bounces ?? '—'"
        icon="arrow-uturn-left"
        :loading="summaryLoading"
        testid="deliverability-stat-bounces" />
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.complaints', { days: windowDays })"
        :value="counts?.recent_complaints ?? '—'"
        icon="hand-raised"
        :loading="summaryLoading"
        testid="deliverability-stat-complaints" />
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.skipped')"
        :value="counts?.sends_skipped ?? '—'"
        icon="shield-check"
        :loading="summaryLoading"
        testid="deliverability-stat-skipped" />
    </div>

    <!-- ===== Sync status (ITEM 2, read-only) ============================== -->
    <div
      class="mt-6"
      data-testid="deliverability-sync-status">
      <h4 class="text-sm font-semibold text-gray-700 dark:text-gray-300">
        {{ t('web.admin.emailtools.deliverability.sync.title') }}
      </h4>

      <!-- Never synced: the feedback sync has not been configured / run. -->
      <div
        v-if="neverSynced"
        class="mt-2 flex items-start gap-3 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 dark:border-amber-900/50 dark:bg-amber-900/20"
        role="alert"
        data-testid="deliverability-sync-never">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="5"
          class="mt-0.5 shrink-0 text-amber-600 dark:text-amber-400" />
        <span class="text-sm text-amber-800 dark:text-amber-200">
          {{ t('web.admin.emailtools.deliverability.sync.neverRun') }}
        </span>
      </div>

      <!-- Per-provider last-sync time + source. -->
      <ul
        v-else
        class="mt-2 space-y-1">
        <li
          v-for="entry in syncEntries"
          :key="entry.provider"
          class="text-sm text-gray-600 dark:text-gray-400"
          :data-testid="`deliverability-sync-${entry.provider}`">
          <span class="font-medium text-gray-900 dark:text-gray-100">{{ entry.provider }}</span>
          <span class="text-gray-400 dark:text-gray-500"> — </span>
          {{ t('web.admin.emailtools.deliverability.sync.lastSynced') }}
          <span class="font-mono">{{ formatDisplayDateTime(entry.last_synced_at) }}</span>
          <span class="text-gray-400 dark:text-gray-500">
            ({{ t('web.admin.emailtools.deliverability.sync.imported', { count: entry.imported }) }})
          </span>
        </li>
      </ul>
    </div>

    <!-- ===== Suppression list ============================================ -->
    <div class="mt-8 border-t border-gray-100 pt-6 dark:border-gray-800">
      <h4 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.deliverability.suppressions.title') }}
      </h4>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.deliverability.suppressions.description') }}
      </p>

      <!-- Manual add (ITEM 6 — guarded; body carries ONLY address, backend
           hardcodes reason='manual'/source='colonel'). Additive/reversible via
           the per-row remove, so the confirm is a plain (non-danger) dialog. -->
      <form
        class="mt-4 flex flex-wrap items-end gap-3"
        @submit.prevent="requestAdd">
        <div class="min-w-[18rem] flex-1">
          <label
            for="deliverability-add"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.suppressions.add.addressLabel') }}
          </label>
          <input
            id="deliverability-add"
            v-model="addAddress"
            type="email"
            data-testid="deliverability-add-input"
            :placeholder="t('web.admin.emailtools.deliverability.suppressions.searchPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="submit"
          data-testid="deliverability-add-submit"
          :disabled="!addAddressValid || addLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50">
          <OIcon
            collection="heroicons"
            name="plus"
            size="4" />
          {{ t('web.admin.emailtools.deliverability.suppressions.add.button') }}
        </button>
      </form>

      <!-- Exact-address lookup (submitted, not live — the endpoint is keyed) -->
      <form
        class="mt-4 flex flex-wrap items-end gap-3"
        @submit.prevent="onSearchSubmit">
        <div class="min-w-[18rem] flex-1">
          <label
            for="deliverability-search"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.suppressions.searchLabel') }}
          </label>
          <input
            id="deliverability-search"
            v-model="searchTerm"
            type="text"
            data-testid="deliverability-search-input"
            :placeholder="t('web.admin.emailtools.deliverability.suppressions.searchPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="submit"
          data-testid="deliverability-search-submit"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
          <OIcon
            collection="heroicons"
            name="magnifying-glass"
            size="4" />
          {{ t('web.admin.emailtools.deliverability.suppressions.searchButton') }}
        </button>
        <button
          v-if="activeSearch"
          type="button"
          data-testid="deliverability-search-clear"
          class="rounded-md px-3 py-2 text-sm font-medium text-gray-500 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-gray-400 dark:hover:text-gray-200"
          @click="onSearchClear">
          {{ t('web.admin.emailtools.deliverability.suppressions.clearButton') }}
        </button>
      </form>

      <p
        v-if="suppressionsError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="deliverability-suppressions-error">
        {{ t('web.admin.emailtools.deliverability.suppressions.loadError') }}
      </p>

      <div class="mt-4">
        <DataTable
          :columns="suppressionColumns"
          :rows="suppressions"
          row-key="address"
          :loading="suppressionsLoading"
          :empty-text="suppressionsEmptyText"
          testid="deliverability-suppressions-table">
          <template #cell-address="{ row }">
            <span class="font-mono text-sm text-gray-900 dark:text-gray-100">{{ row.address }}</span>
          </template>
          <template #cell-reason="{ row }">
            <span
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="kindClass(row.reason)">
              {{ row.reason }}
            </span>
          </template>
          <template #cell-source="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.source || '—' }}</span>
          </template>
          <template #cell-created="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ formatDisplayDateTime(row.created) }}</span>
          </template>
          <template #cell-actions="{ row }">
            <button
              type="button"
              :data-testid="`deliverability-remove-${row.address}`"
              class="rounded px-2 py-1 text-sm font-medium text-red-600 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 dark:text-red-400 dark:hover:bg-red-900/30"
              @click="requestRemove(row.address)">
              {{ t('web.admin.emailtools.deliverability.suppressions.remove.button') }}
            </button>
          </template>
        </DataTable>

        <KitPagination
          v-if="suppressionsMeta && suppressionsMeta.total_pages > 1"
          :pagination="suppressionsMeta"
          :loading="suppressionsLoading"
          @update:page="fetchSuppressions"
          @update:per-page="onSuppressionsPerPage" />
      </div>
    </div>

    <!-- ===== Recipient lookup (item 10 — local store + live provider) ==== -->
    <div class="mt-8 border-t border-gray-100 pt-6 dark:border-gray-800">
      <h4 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.deliverability.lookup.title') }}
      </h4>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.deliverability.lookup.description') }}
      </p>

      <form
        class="mt-4 flex flex-wrap items-end gap-3"
        @submit.prevent="onLookupSubmit">
        <div class="min-w-[18rem] flex-1">
          <label
            for="deliverability-lookup"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.lookup.addressLabel') }}
          </label>
          <input
            id="deliverability-lookup"
            v-model="lookupAddress"
            type="text"
            data-testid="deliverability-lookup-input"
            :placeholder="t('web.admin.emailtools.deliverability.suppressions.searchPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="submit"
          data-testid="deliverability-lookup-submit"
          :disabled="lookupLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50">
          <OIcon
            collection="heroicons"
            name="magnifying-glass"
            size="4" />
          {{ t('web.admin.emailtools.deliverability.lookup.submit') }}
        </button>
        <button
          v-if="activeLookupAddress"
          type="button"
          data-testid="deliverability-lookup-clear"
          class="rounded-md px-3 py-2 text-sm font-medium text-gray-500 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-gray-400 dark:hover:text-gray-200"
          @click="onLookupClear">
          {{ t('web.admin.emailtools.deliverability.suppressions.clearButton') }}
        </button>
      </form>

      <!-- Local + provider status side by side, both keyed by the SAME
           normalized address. Local is always readable; the provider column
           honors capability/available. -->
      <div
        v-if="lookupResult"
        class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2"
        data-testid="deliverability-lookup-result">
        <!-- Local store (authoritative, always present). -->
        <div class="rounded-md border border-gray-200 p-4 dark:border-gray-800">
          <h5 class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.lookup.local') }}
          </h5>
          <p class="font-mono text-sm text-gray-900 dark:text-gray-100">{{ lookupResult.address }}</p>
          <div class="mt-2 flex items-center gap-2">
            <span
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="lookupResult.local.suppressed
                ? 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300'
                : 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300'"
              data-testid="deliverability-lookup-local-status">
              {{
                lookupResult.local.suppressed
                  ? t('web.admin.emailtools.deliverability.lookup.suppressed')
                  : t('web.admin.emailtools.deliverability.lookup.notSuppressed')
              }}
            </span>
          </div>
          <p
            v-if="lookupResult.local.suppressed"
            class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.lookup.reason') }}:
            <span class="font-mono">{{ lookupResult.local.reason || '—' }}</span>
            <span class="text-gray-400 dark:text-gray-500"> · </span>
            {{ t('web.admin.emailtools.deliverability.lookup.source') }}:
            <span class="font-mono">{{ lookupResult.local.source || '—' }}</span>
          </p>
        </div>

        <!-- Live provider read (capability / available gated). -->
        <div class="rounded-md border border-gray-200 p-4 dark:border-gray-800">
          <h5 class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.lookup.provider') }}
            <span class="ml-1 font-normal normal-case text-gray-400 dark:text-gray-500">{{ lookupProvider }}</span>
          </h5>

          <p
            v-if="lookupProviderUnsupported"
            class="text-sm text-gray-500 dark:text-gray-400"
            data-testid="deliverability-lookup-provider-unsupported">
            {{ t('web.admin.emailtools.deliverability.lookup.unavailable') }}
          </p>
          <p
            v-else-if="lookupProviderFailed"
            class="text-sm text-red-700 dark:text-red-300"
            role="alert"
            data-testid="deliverability-lookup-provider-error">
            {{ lookupResult.error || t('web.admin.emailtools.deliverability.lookup.unavailable') }}
          </p>
          <div
            v-else-if="lookupResult.provider_result"
            data-testid="deliverability-lookup-provider-result">
            <span
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="lookupResult.provider_result.suppressed
                ? 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300'
                : 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300'">
              {{
                lookupResult.provider_result.suppressed
                  ? t('web.admin.emailtools.deliverability.lookup.suppressed')
                  : t('web.admin.emailtools.deliverability.lookup.notSuppressed')
              }}
            </span>
            <p
              v-if="lookupResult.provider_result.suppressed"
              class="mt-2 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.admin.emailtools.deliverability.lookup.reason') }}:
              <span class="font-mono">{{ lookupResult.provider_result.reason || '—' }}</span>
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- ===== Recent events feed ========================================== -->
    <div class="mt-8 border-t border-gray-100 pt-6 dark:border-gray-800">
      <h4 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.deliverability.events.title') }}
      </h4>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.deliverability.events.description') }}
      </p>

      <p
        v-if="eventsError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="deliverability-events-error">
        {{ t('web.admin.emailtools.deliverability.events.loadError') }}
      </p>

      <div class="mt-4">
        <DataTable
          :columns="eventColumns"
          :rows="events"
          row-key="id"
          :loading="eventsLoading"
          :empty-text="t('web.admin.emailtools.deliverability.events.empty')"
          testid="deliverability-events-table">
          <template #cell-created="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ formatDisplayDateTime(row.created) }}</span>
          </template>
          <template #cell-kind="{ row }">
            <span
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="kindClass(row.kind)">
              {{ kindLabel(row.kind) }}
            </span>
          </template>
          <template #cell-address="{ row }">
            <span class="font-mono text-sm text-gray-900 dark:text-gray-100">{{ row.address }}</span>
          </template>
          <template #cell-source="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.source || '—' }}</span>
          </template>
          <template #cell-reason="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.reason || '—' }}</span>
          </template>
        </DataTable>
      </div>
    </div>

    <!-- ===== Recent sends feed (item 9 — provider's OWN message API) ===== -->
    <div class="mt-8 border-t border-gray-100 pt-6 dark:border-gray-800">
      <h4 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.deliverability.messages.title') }}
      </h4>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.deliverability.messages.description') }}
      </p>

      <!-- capability=false (e.g. SES has no per-message API): static empty-state,
           no table, no retry. -->
      <div
        v-if="!messagesCapability"
        class="mt-4 flex items-start gap-3 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 dark:border-gray-800 dark:bg-gray-800/40"
        data-testid="deliverability-messages-unsupported">
        <OIcon
          collection="heroicons"
          name="information-circle"
          size="5"
          class="mt-0.5 shrink-0 text-gray-400 dark:text-gray-500" />
        <span class="text-sm text-gray-600 dark:text-gray-300">
          {{ t('web.admin.emailtools.deliverability.messages.notSupported', { provider: messagesProvider }) }}
        </span>
      </div>

      <template v-else>
        <p
          v-if="messagesFailed"
          class="mt-3 text-sm text-red-700 dark:text-red-300"
          role="alert"
          data-testid="deliverability-messages-error">
          {{ t('web.admin.emailtools.deliverability.messages.error') }}
        </p>

        <div class="mt-4">
          <DataTable
            :columns="messageColumns"
            :rows="messages"
            row-key="id"
            :loading="messagesLoading"
            :empty-text="t('web.admin.emailtools.deliverability.messages.empty')"
            testid="deliverability-messages-table">
            <template #cell-created_at="{ row }">
              <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.created_at ? formatDisplayDateTime(row.created_at) : '—' }}</span>
            </template>
            <template #cell-status="{ row }">
              <span
                class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
                :class="messageStatusClass(row.status)">
                {{ messageStatusLabel(row.status) }}
              </span>
            </template>
            <template #cell-subject="{ row }">
              <span class="text-sm text-gray-900 dark:text-gray-100">{{ row.subject || '—' }}</span>
            </template>
            <template #cell-to="{ row }">
              <span class="font-mono text-sm text-gray-500 dark:text-gray-400">{{ row.to.join(', ') || '—' }}</span>
            </template>
          </DataTable>
        </div>
      </template>
    </div>

    <!-- Suppression removal: one-click confirm (the unban idiom). Removing a
         suppression re-enables sending to a known-bad address, so the dialog
         copy says exactly that; the op audits server-side (CONTRACT 4). -->
    <AdminConfirmDialog
      v-model:open="removeDialogOpen"
      :title="t('web.admin.emailtools.deliverability.suppressions.remove.confirmTitle')"
      :description="
        t('web.admin.emailtools.deliverability.suppressions.remove.confirmDescription', {
          address: removeTarget,
        })
      "
      :confirm-token="undefined"
      variant="danger"
      :confirm-text="t('web.admin.emailtools.deliverability.suppressions.remove.button')"
      :loading="removeLoading"
      :error="removeError"
      @confirm="onRemoveConfirm"
      @cancel="onRemoveCancel" />

    <!-- Manual add: guarded confirm (ITEM 6). Additive/reversible, so a plain
         (non-danger) dialog. The op audits server-side (CONTRACT 4). -->
    <AdminConfirmDialog
      v-model:open="addDialogOpen"
      :title="t('web.admin.emailtools.deliverability.suppressions.add.confirmTitle')"
      :description="
        t('web.admin.emailtools.deliverability.suppressions.add.confirmDescription', {
          address: addAddress.trim(),
        })
      "
      :confirm-token="undefined"
      variant="default"
      :confirm-text="t('web.admin.emailtools.deliverability.suppressions.add.button')"
      :loading="addLoading"
      :error="addError"
      @confirm="onAddConfirm"
      @cancel="onAddCancel" />
  </section>
</template>
