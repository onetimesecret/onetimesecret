<!-- src/apps/admin/components/jobs/JobsDlqSection.vue -->

<script setup lang="ts">
  import { dlqDeepScanCommand } from '@/apps/admin/components/jobs/jobsFormat';
  import {
    AdminConfirmDialog,
    DataTable,
    DetailDrawer,
    JsonViewer,
    KitPagination,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminDestructiveMutation } from '@/apps/admin/composables/useAdminDestructiveMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { useAdminDlq } from '@/apps/admin/stores/useAdminDlq';
  import { confirmHeaders } from '@/apps/admin/utils/confirmHeader';
  import { reasonBody } from '@/apps/admin/utils/operatorReason';
  import type { ColonelDlqSummary } from '@/schemas/api/internal/responses/colonel-queue';
  import {
    colonelDlqMessageDetailResponseSchema,
    colonelDlqMessageDiscardResponseSchema,
    colonelDlqMessageReplayResponseSchema,
    colonelDlqMessagesResponseSchema,
    DLQ_MESSAGE_OUTCOME_UNCONFIRMED,
    DLQ_REPLAY_OUTCOME_NO_ORIGINAL_QUEUE,
    DLQ_REPLAY_OUTCOME_UNROUTABLE,
    DLQ_REPLAY_OUTCOME_UNROUTABLE_LOST,
  } from '@/schemas/api/internal/responses/colonel-queue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Dead-letter queues (#4343, Jobs screen section 2).
   *
   * - LIST: the configured DLQs with their depth, from {@link useAdminDlq}.
   * - PEEK DRAWER: a row opens {@link DetailDrawer} on
   *   `GET /api/colonel/queues/dlq/:queue` — a bounded sample of messages.
   * - INSPECT: one message's full detail (headers, x-death, whole payload) from
   *   `GET …/messages/:message_id`, shown inline under that message.
   * - REPLAY (tier 2) / DISCARD (tier 1): one message by id, through
   *   {@link AdminConfirmDialog} typed confirmation + optional reason. Only
   *   Discard is `variant="danger"` — it is the irreversible one.
   *
   * MISSES ARE NOT ERRORS. All three per-message verbs find the message with a
   * bounded scan from the head of the queue. A miss on a valid queue is HTTP
   * 200 with `found: false` (`outcome: 'not_visible'`): a worker may be holding
   * the delivery, someone may have replayed it first, or it sits deeper than
   * the scan looked (`truncated`). The console says which, plainly, and gives
   * the CLI command that can scan deeper.
   *
   * KEPT, LOST AND UNCONFIRMED. A replay that found the message but had nowhere
   * to send it (`no_original_queue`, `unroutable`) leaves it in the DLQ: a
   * warning, never success. A replay whose copy was rejected AND could not be
   * put back (`unroutable_lost`) may have lost it: an error that says so. A
   * replay or discard the broker did not confirm (`unconfirmed`) reads "outcome
   * unknown", never success and never "could not be replayed / not discarded".
   * The outcome is always read before the counts.
   *
   * IN-PAGE STATE: the open queue, the inspected message and the last action
   * result live in refs here, never in the query string — a query change would
   * remount the routed view and drop all of it.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const store = useAdminDlq();
  const { dlqs, pagination, connected, loading, error, validationError } = storeToRefs(store);

  const failed = computed(() => error.value !== null || validationError.value !== null);

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // Captured in `store.error`; the banner + retry handle it.
    }
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  const columns = computed<DataTableColumn<ColonelDlqSummary>[]>(() => [
    { key: 'queue', label: t('web.admin.jobs.dlq.columns.queue') },
    { key: 'messages', label: t('web.admin.jobs.dlq.columns.messages'), align: 'right' },
    { key: 'consumers', label: t('web.admin.jobs.dlq.columns.consumers'), align: 'right' },
    { key: 'actions', label: t('web.admin.jobs.dlq.columns.actions'), align: 'right' },
  ]);

  /**
   * The `:queue` URL segment AND the X-OTS-Confirm token. The server confirms
   * against its sanitized `params['queue']`, so the two must be the same
   * string — the short name the CLI also takes (`billing.event`).
   */
  function shortName(queue: string): string {
    return queue.replace(/^dlq\./, '');
  }

  function queueUrl(short: string): string {
    return `/api/colonel/queues/dlq/${encodeURIComponent(short)}`;
  }

  function messageUrl(short: string, messageId: string): string {
    return `${queueUrl(short)}/messages/${encodeURIComponent(messageId)}`;
  }

  // ---- Peek drawer ----------------------------------------------------------

  const drawerOpen = ref(false);
  const selectedQueue = ref<ColonelDlqSummary | null>(null);
  const selectedShort = computed(() =>
    selectedQueue.value ? shortName(selectedQueue.value.queue) : ''
  );

  const {
    data: peekData,
    loading: peekLoading,
    error: peekError,
    validationError: peekValidationError,
    notFound: peekNotFound,
    load: loadPeek,
    reset: resetPeek,
  } = useResourceFetch({
    url: () => queueUrl(selectedShort.value),
    schema: colonelDlqMessagesResponseSchema,
    context: 'ColonelDlqMessagesResponse',
  });

  /**
   * Short name of the queue the peek reader was last pointed at. Opening a
   * DIFFERENT queue resets the reader first, so queue A's messages (and their
   * row actions) never sit under queue B's heading while B loads; re-peeking
   * the SAME queue (refresh, after a replay/discard) keeps the rows up so
   * they do not flash.
   */
  let peekedShort: string | null = null;

  const peekRecord = computed(() => peekData.value?.record ?? null);
  const peekMessages = computed(() => peekData.value?.details?.messages ?? []);
  const peekFailed = computed(
    () => (peekError.value !== null && !peekNotFound.value) || peekValidationError.value !== null
  );

  function repeek(): void {
    loadPeek().catch(() => {});
  }

  // ---- Inspect (inline, one message at a time) ------------------------------

  const inspectedId = ref<string | null>(null);

  const {
    data: inspectData,
    loading: inspectLoading,
    error: inspectError,
    validationError: inspectValidationError,
    load: loadInspect,
    reset: resetInspect,
  } = useResourceFetch({
    url: () => messageUrl(selectedShort.value, inspectedId.value ?? ''),
    schema: colonelDlqMessageDetailResponseSchema,
    context: 'ColonelDlqMessageDetailResponse',
  });

  const inspectRecord = computed(() => inspectData.value?.record ?? null);
  const inspectMessage = computed(() => inspectData.value?.details?.message ?? null);
  const inspectFailed = computed(
    () => inspectError.value !== null || inspectValidationError.value !== null
  );

  function inspect(messageId: string): void {
    // Switching messages: drop the previous detail so it is never shown under
    // the new message's row while its load settles.
    if (inspectedId.value !== messageId) resetInspect();
    inspectedId.value = messageId;
    loadInspect().catch(() => {});
  }

  function closeInspect(): void {
    inspectedId.value = null;
    resetInspect();
  }

  // ---- Replay / discard (guarded) --------------------------------------------

  type MessageVerb = 'replay' | 'discard';

  /**
   * What the last replay/discard did, as read from its ack:
   *
   * - `unverified`  the 2xx body did not match its schema — outcome unknown.
   * - `not_visible` the bounded scan did not see the message.
   * - `kept`        replay found the message but could not send it anywhere
   *                 (`no_original_queue` / `unroutable`); it is still in the DLQ.
   * - `lost`        replay: the original queue rejected the copy and putting it
   *                 back into the DLQ failed (`unroutable_lost`). May be lost.
   * - `unconfirmed` the broker did not confirm a commit. Discard: the message
   *                 may or may not be gone. Replay: it may have been replayed or
   *                 dropped, or may still be in the DLQ; the counts are not
   *                 reliable. Never "done", never "failed".
   * - `done`        replayed (replay) or dropped (discard).
   * - `failed`      found, not done, for any other reason.
   */
  type MessageActionState =
    | 'unverified'
    | 'not_visible'
    | 'kept'
    | 'lost'
    | 'unconfirmed'
    | 'done'
    | 'failed';

  interface MessageActionResult {
    verb: MessageVerb;
    messageId: string;
    state: MessageActionState;
    /** The server's `outcome`, when it sent one. */
    outcome: string | null;
    scanned: number;
    truncated: boolean;
    /** Server text: replay `details.errors`, unconfirmed discard `details.message`. */
    notes: string[];
  }

  /**
   * Replay outcomes that override the counts. Read BEFORE `found` / `replayed`:
   * for these the counts are either zero by design or not reliable.
   */
  function replayOutcomeState(outcome: string | null): MessageActionState | null {
    if (outcome === null) return null;
    if (outcome === DLQ_MESSAGE_OUTCOME_UNCONFIRMED) return 'unconfirmed';
    if (outcome === DLQ_REPLAY_OUTCOME_UNROUTABLE_LOST) return 'lost';
    if (KEPT_OUTCOME_KEYS.has(outcome)) return 'kept';
    return null;
  }

  /** Replay outcomes where the message was found and deliberately left in the DLQ. */
  const KEPT_OUTCOME_KEYS: ReadonlyMap<string, string> = new Map([
    [DLQ_REPLAY_OUTCOME_NO_ORIGINAL_QUEUE, 'web.admin.jobs.dlq.replay.noOriginalQueue'],
    [DLQ_REPLAY_OUTCOME_UNROUTABLE, 'web.admin.jobs.dlq.replay.unroutable'],
  ]);

  const actionDialogOpen = ref(false);
  const actionVerb = ref<MessageVerb>('replay');
  const actionMessageId = ref('');
  /** Short queue name frozen when the dialog opened: URL segment + token. */
  const actionQueue = ref('');
  const lastAction = ref<MessageActionResult | null>(null);

  function unverifiedResult(verb: MessageVerb, messageId: string): MessageActionResult {
    return {
      verb,
      messageId,
      state: 'unverified',
      outcome: null,
      scanned: 0,
      truncated: false,
      notes: [],
    };
  }

  /** Read a replay ack. A 2xx with an unreadable body is reported, not assumed. */
  function readReplayAck(messageId: string, payload: unknown): MessageActionResult {
    const parsed = gracefulParse(
      colonelDlqMessageReplayResponseSchema,
      payload,
      'ColonelDlqMessageReplayResponse'
    );
    if (!parsed.ok) return unverifiedResult('replay', messageId);
    const record = parsed.data.record;
    const outcome = record.outcome ?? null;
    let state = replayOutcomeState(outcome);
    if (state === null) {
      if (!record.found) state = 'not_visible';
      else state = record.replayed > 0 ? 'done' : 'failed';
    }
    return {
      verb: 'replay',
      messageId,
      state,
      outcome,
      scanned: record.scanned,
      truncated: record.truncated,
      notes: (parsed.data.details?.errors ?? []).map((e) => e.error),
    };
  }

  /**
   * Read a discard ack. `unconfirmed` is checked first: `discarded: false`
   * there means "the broker did not say", not "found but not discarded".
   */
  function readDiscardAck(messageId: string, payload: unknown): MessageActionResult {
    const parsed = gracefulParse(
      colonelDlqMessageDiscardResponseSchema,
      payload,
      'ColonelDlqMessageDiscardResponse'
    );
    if (!parsed.ok) return unverifiedResult('discard', messageId);
    const record = parsed.data.record;
    const outcome = record.outcome ?? null;
    const unconfirmed = outcome === DLQ_MESSAGE_OUTCOME_UNCONFIRMED;
    let state: MessageActionState;
    if (unconfirmed) state = 'unconfirmed';
    else if (!record.found) state = 'not_visible';
    else state = record.discarded ? 'done' : 'failed';
    const message = parsed.data.details?.message;
    return {
      verb: 'discard',
      messageId,
      state,
      outcome,
      scanned: record.scanned,
      truncated: record.truncated,
      notes: unconfirmed && message ? [message] : [],
    };
  }

  /** The i18n key for a kept replay's explanation. */
  function keptKey(result: MessageActionResult): string {
    return KEPT_OUTCOME_KEYS.get(result.outcome ?? '') ?? 'web.admin.jobs.dlq.replay.failed';
  }

  /** Discard is the way out for a message that records no original queue. */
  function suggestsDiscard(result: MessageActionResult): boolean {
    return result.state === 'kept' && result.outcome === DLQ_REPLAY_OUTCOME_NO_ORIGINAL_QUEUE;
  }

  const {
    loading: actionLoading,
    error: actionError,
    run: runAction,
    reset: resetAction,
  } = useAdminDestructiveMutation(async (reason?: string) => {
    const verb = actionVerb.value;
    const messageId = actionMessageId.value;
    const queue = actionQueue.value;
    if (!messageId || !queue) throw new Error('No message selected');
    const response = await $api.post(
      `${messageUrl(queue, messageId)}/${verb}`,
      { dry_run: false, ...reasonBody(reason) },
      { headers: confirmHeaders(queue) }
    );
    lastAction.value =
      verb === 'replay'
        ? readReplayAck(messageId, response.data)
        : readDiscardAck(messageId, response.data);
  });

  function requestAction(verb: MessageVerb, messageId: string): void {
    if (!selectedShort.value || !messageId) return;
    actionVerb.value = verb;
    actionMessageId.value = messageId;
    actionQueue.value = selectedShort.value;
    // A stale result must never read as this action's outcome.
    lastAction.value = null;
    resetAction();
    actionDialogOpen.value = true;
  }

  /** One notification per action, matched to what actually happened. */
  function notifyAction(result: MessageActionResult): void {
    switch (result.state) {
      case 'unverified':
        notifications.show(t('web.admin.jobs.dlq.result.unverified'), 'warning');
        break;
      case 'not_visible':
        notifications.show(t('web.admin.jobs.dlq.result.notVisible'), 'warning');
        break;
      case 'kept':
        notifications.show(t(keptKey(result)), 'warning');
        break;
      case 'lost':
        notifications.show(t('web.admin.jobs.dlq.replay.unroutableLost'), 'error');
        break;
      case 'unconfirmed':
        notifications.show(t('web.admin.jobs.dlq.result.unconfirmed'), 'warning');
        break;
      case 'done':
        notifications.show(t(`web.admin.jobs.dlq.${result.verb}.success`), 'success');
        break;
      default:
        notifications.show(t(`web.admin.jobs.dlq.${result.verb}.failed`), 'error');
    }
  }

  async function onActionConfirm(reason?: string): Promise<void> {
    const ok = await runAction(reason);
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    actionDialogOpen.value = false;
    const result = lastAction.value ?? unverifiedResult(actionVerb.value, actionMessageId.value);
    notifyAction(result);

    // Whatever happened, the inspected copy of this message is now stale.
    if (inspectedId.value === result.messageId) closeInspect();
    repeek();
    await fetchPage(pagination.value?.page ?? 1);
  }

  function onActionCancel(): void {
    actionDialogOpen.value = false;
    resetAction();
  }

  const actionQueueFull = computed(() => selectedQueue.value?.queue ?? actionQueue.value);

  // ---- Drawer lifecycle -------------------------------------------------------

  function openQueue(row: ColonelDlqSummary): void {
    selectedQueue.value = row;
    const short = shortName(row.queue);
    if (short !== peekedShort) resetPeek();
    peekedShort = short;
    closeInspect();
    lastAction.value = null;
    drawerOpen.value = true;
    repeek();
  }

  function closeDrawer(): void {
    drawerOpen.value = false;
    selectedQueue.value = null;
    // Forget the peeked queue so reopening it starts from a reset reader:
    // rows from the closed drawer may have been replayed or discarded since.
    peekedShort = null;
    closeInspect();
    lastAction.value = null;
  }

  const num = (value: number | undefined | null): string =>
    typeof value === 'number' ? value.toLocaleString() : '—';

  onMounted(() => fetchPage(1));
</script>

<template>
  <section
    class="mb-10"
    data-testid="jobs-dlq">
    <div class="mb-3 flex items-end justify-between gap-4">
      <div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.jobs.dlq.title') }}
        </h3>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.admin.jobs.dlq.description') }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
        :disabled="loading"
        data-testid="jobs-dlq-refresh"
        @click="fetchPage(pagination?.page ?? 1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.jobs.refresh') }}
      </button>
    </div>

    <!-- Error (network/HTTP or contract mismatch) -->
    <div
      v-if="failed"
      class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="jobs-dlq-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.jobs.dlq.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.jobs.retry') }}
      </button>
    </div>

    <template v-else>
      <!-- Broker down: depths below are unreadable, not zero. -->
      <p
        v-if="connected === false"
        class="mb-3 flex items-center gap-1 text-xs text-amber-700 dark:text-amber-400"
        data-testid="jobs-dlq-disconnected">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="4" />
        {{ t('web.admin.jobs.dlq.disconnected') }}
      </p>

      <div
        class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <DataTable
          :columns="columns"
          :rows="dlqs"
          row-key="queue"
          :loading="loading"
          :empty-text="t('web.admin.jobs.dlq.empty')"
          clickable-rows
          testid="dlq-table"
          @row-click="openQueue">
          <template #cell-queue="{ row }">
            <span class="font-mono text-sm text-gray-900 dark:text-white">{{ row.queue }}</span>
          </template>
          <template #cell-messages="{ row }">
            <span
              v-if="row.error"
              class="text-xs text-amber-700 dark:text-amber-400">
              {{ row.error }}
            </span>
            <span
              v-else
              class="font-mono text-sm tabular-nums">
              {{ num(row.messages) }}
            </span>
          </template>
          <template #cell-consumers="{ row }">
            <span class="font-mono text-sm tabular-nums">{{ num(row.consumers) }}</span>
          </template>
          <template #cell-actions="{ row }">
            <button
              type="button"
              class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              :data-testid="`dlq-peek-${row.queue}`"
              @click.stop="openQueue(row)">
              <OIcon
                collection="heroicons"
                name="magnifying-glass"
                size="4" />
              {{ t('web.admin.jobs.dlq.peek') }}
            </button>
          </template>
        </DataTable>
      </div>

      <KitPagination
        v-if="pagination"
        :pagination="pagination"
        :loading="loading"
        class="mt-4"
        @update:page="fetchPage"
        @update:per-page="onPerPageChange" />
    </template>

    <!-- Peek drawer -->
    <DetailDrawer
      v-model:open="drawerOpen"
      :title="t('web.admin.jobs.dlq.drawer.title')"
      :subtitle="selectedQueue?.queue"
      width-class="max-w-2xl"
      testid="dlq-drawer"
      @close="closeDrawer">
      <!-- Last action on this queue, kept until the next action or close. -->
      <div
        v-if="lastAction"
        class="mb-4 rounded-md border border-gray-200 bg-gray-50 px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-800/60"
        data-testid="dlq-last-action">
        <p class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.jobs.dlq.result.title') }}
          <span class="ml-1 font-mono tracking-normal normal-case">{{ lastAction.messageId }}</span>
        </p>
        <p
          v-if="lastAction.state === 'unverified'"
          class="mt-1 text-amber-800 dark:text-amber-300">
          {{ t('web.admin.jobs.dlq.result.unverified') }}
        </p>
        <template v-else-if="lastAction.state === 'not_visible'">
          <p
            class="mt-1 text-amber-800 dark:text-amber-300"
            data-testid="dlq-last-action-not-visible">
            {{ t('web.admin.jobs.dlq.notVisible', { scanned: lastAction.scanned }) }}
          </p>
          <template v-if="lastAction.truncated">
            <p
              class="mt-1 text-amber-800 dark:text-amber-300"
              data-testid="dlq-last-action-truncated">
              {{ t('web.admin.jobs.dlq.truncated', { scanned: lastAction.scanned }) }}
            </p>
            <code
              class="mt-1 block font-mono text-xs break-all text-gray-900 dark:text-gray-100"
              data-testid="dlq-last-action-deep-scan">
              {{ dlqDeepScanCommand(selectedShort, lastAction.messageId) }}
            </code>
          </template>
        </template>
        <!-- Found, deliberately left in the DLQ: a warning, never success. -->
        <template v-else-if="lastAction.state === 'kept'">
          <p
            class="mt-1 flex items-start gap-1 text-amber-800 dark:text-amber-300"
            data-testid="dlq-last-action-kept">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              size="4"
              class="mt-0.5 shrink-0" />
            {{ t(keptKey(lastAction)) }}
          </p>
          <p
            v-for="(note, index) in lastAction.notes"
            :key="index"
            class="mt-1 font-mono text-xs break-all text-gray-700 dark:text-gray-300"
            data-testid="dlq-last-action-note">
            {{ note }}
          </p>
          <button
            v-if="suggestsDiscard(lastAction)"
            type="button"
            class="mt-2 inline-flex items-center gap-1 rounded-md border border-red-300 px-2.5 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
            data-testid="dlq-last-action-discard"
            @click="requestAction('discard', lastAction.messageId)">
            <OIcon
              collection="heroicons"
              name="trash"
              size="4" />
            {{ t('web.admin.jobs.dlq.discard.button') }}
          </button>
        </template>
        <!-- Replay copy rejected and not put back: the message may be gone. -->
        <template v-else-if="lastAction.state === 'lost'">
          <p
            class="mt-1 flex items-start gap-1 font-medium text-amber-800 dark:text-amber-300"
            data-testid="dlq-last-action-lost">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              size="4"
              class="mt-0.5 shrink-0" />
            {{ t('web.admin.jobs.dlq.replay.unroutableLost') }}
          </p>
          <p
            v-for="(note, index) in lastAction.notes"
            :key="index"
            class="mt-1 font-mono text-xs break-all text-gray-700 dark:text-gray-300"
            data-testid="dlq-last-action-note">
            {{ note }}
          </p>
        </template>
        <!-- The broker did not confirm (replay or discard): outcome unknown. -->
        <template v-else-if="lastAction.state === 'unconfirmed'">
          <p
            class="mt-1 flex items-start gap-1 text-amber-800 dark:text-amber-300"
            data-testid="dlq-last-action-unconfirmed">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              size="4"
              class="mt-0.5 shrink-0" />
            {{ t('web.admin.jobs.dlq.result.unconfirmed') }}
          </p>
          <p
            v-for="(note, index) in lastAction.notes"
            :key="index"
            class="mt-1 font-mono text-xs break-all text-gray-700 dark:text-gray-300"
            data-testid="dlq-last-action-note">
            {{ note }}
          </p>
        </template>
        <p
          v-else-if="lastAction.state === 'done'"
          class="mt-1 text-gray-900 dark:text-gray-100"
          data-testid="dlq-last-action-done">
          {{ t(`web.admin.jobs.dlq.${lastAction.verb}.success`) }}
        </p>
        <template v-else>
          <p
            class="mt-1 text-amber-800 dark:text-amber-300"
            data-testid="dlq-last-action-failed">
            {{ t(`web.admin.jobs.dlq.${lastAction.verb}.failed`) }}
          </p>
          <p
            v-for="(note, index) in lastAction.notes"
            :key="index"
            class="mt-1 font-mono text-xs break-all text-gray-700 dark:text-gray-300"
            data-testid="dlq-last-action-note">
            {{ note }}
          </p>
        </template>
      </div>

      <!-- Loading -->
      <div
        v-if="peekLoading && !peekRecord"
        class="flex items-center justify-center py-16 text-gray-500 dark:text-gray-400"
        data-testid="dlq-drawer-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="6"
          class="animate-spin motion-reduce:animate-none" />
        <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
      </div>

      <!-- Unknown queue -->
      <p
        v-else-if="peekNotFound"
        class="px-2 py-12 text-center text-sm text-gray-500 dark:text-gray-400"
        data-testid="dlq-drawer-not-found">
        {{ t('web.admin.jobs.dlq.drawer.notFound') }}
      </p>

      <!-- Load error -->
      <div
        v-else-if="peekFailed"
        class="px-2 py-12 text-center"
        role="alert"
        data-testid="dlq-drawer-error">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.jobs.dlq.drawer.loadError') }}
        </p>
        <button
          type="button"
          class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="repeek">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.jobs.retry') }}
        </button>
      </div>

      <!-- Loaded -->
      <div
        v-else-if="peekRecord"
        data-testid="dlq-drawer-content">
        <div class="mb-3 flex items-center justify-between gap-3">
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {{
              t('web.admin.jobs.dlq.drawer.summary', {
                showing: peekRecord.showing,
                total: peekRecord.total_messages,
              })
            }}
          </p>
          <button
            type="button"
            class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
            :disabled="peekLoading"
            data-testid="dlq-drawer-refresh"
            @click="repeek">
            <OIcon
              collection="heroicons"
              name="arrow-path"
              size="4" />
            {{ t('web.admin.jobs.refresh') }}
          </button>
        </div>

        <p
          v-if="peekMessages.length === 0"
          class="py-8 text-center text-sm text-gray-500 dark:text-gray-400"
          data-testid="dlq-drawer-empty">
          {{ t('web.admin.jobs.dlq.drawer.empty') }}
        </p>

        <ul
          v-else
          class="space-y-3">
          <li
            v-for="(message, index) in peekMessages"
            :key="message.message_id ?? `index-${index}`"
            class="rounded-lg border border-gray-200 bg-white p-3 dark:border-gray-700 dark:bg-gray-900"
            :data-testid="`dlq-message-${message.message_id ?? index}`">
            <div class="flex items-start justify-between gap-3">
              <span class="font-mono text-xs break-all text-gray-900 dark:text-white">
                {{ message.message_id ?? '—' }}
              </span>
              <span class="shrink-0 text-xs text-gray-500 dark:text-gray-400">
                {{ message.age }}
              </span>
            </div>

            <dl class="mt-2 grid grid-cols-1 gap-x-4 gap-y-1 text-xs sm:grid-cols-2">
              <div>
                <dt class="text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.jobs.dlq.fields.originalQueue') }}
                </dt>
                <dd class="font-mono text-gray-900 dark:text-gray-100">
                  {{ message.original_queue ?? '—' }}
                </dd>
              </div>
              <div>
                <dt class="text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.jobs.dlq.fields.deathReason') }}
                </dt>
                <dd class="font-mono text-gray-900 dark:text-gray-100">
                  {{ message.death_reason ?? '—' }}
                  <span v-if="message.death_count">× {{ message.death_count }}</span>
                </dd>
              </div>
              <div
                v-if="message.error"
                class="sm:col-span-2">
                <dt class="text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.jobs.dlq.fields.error') }}
                </dt>
                <dd class="font-mono break-all text-amber-800 dark:text-amber-300">
                  {{ message.error }}
                </dd>
              </div>
            </dl>

            <pre
              v-if="message.payload_preview"
              class="mt-2 max-h-24 overflow-auto rounded bg-gray-50 p-2 font-mono text-xs break-all whitespace-pre-wrap text-gray-700 dark:bg-gray-800 dark:text-gray-300"
              :aria-label="t('web.admin.jobs.dlq.fields.payload')"
              >{{ message.payload_preview }}</pre
            >

            <!-- Row actions: only a message with an id can be addressed. -->
            <div
              v-if="message.message_id"
              class="mt-3 flex flex-wrap items-center gap-2">
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                :data-testid="`dlq-inspect-${message.message_id}`"
                @click="
                  inspectedId === message.message_id ? closeInspect() : inspect(message.message_id)
                ">
                <OIcon
                  collection="heroicons"
                  name="eye"
                  size="4" />
                {{
                  inspectedId === message.message_id
                    ? t('web.admin.jobs.dlq.inspect.hide')
                    : t('web.admin.jobs.dlq.inspect.button')
                }}
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                :data-testid="`dlq-replay-${message.message_id}`"
                @click="requestAction('replay', message.message_id)">
                <OIcon
                  collection="heroicons"
                  name="arrow-uturn-left"
                  size="4" />
                {{ t('web.admin.jobs.dlq.replay.button') }}
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-md border border-red-300 px-2.5 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
                :data-testid="`dlq-discard-${message.message_id}`"
                @click="requestAction('discard', message.message_id)">
                <OIcon
                  collection="heroicons"
                  name="trash"
                  size="4" />
                {{ t('web.admin.jobs.dlq.discard.button') }}
              </button>
            </div>
            <p
              v-else
              class="mt-3 text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.jobs.dlq.drawer.noMessageId') }}
            </p>

            <!-- Inspect panel for this message -->
            <div
              v-if="message.message_id && inspectedId === message.message_id"
              class="mt-3 border-t border-gray-200 pt-3 dark:border-gray-700"
              :data-testid="`dlq-inspect-panel-${message.message_id}`">
              <p
                v-if="inspectLoading && !inspectRecord"
                class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.COMMON.loading') }}
              </p>
              <div
                v-else-if="inspectFailed"
                class="flex items-center justify-between gap-3"
                role="alert">
                <span class="text-xs text-red-800 dark:text-red-200">
                  {{ t('web.admin.jobs.dlq.inspect.loadError') }}
                </span>
                <button
                  type="button"
                  class="text-xs font-medium text-gray-700 underline hover:text-gray-900 dark:text-gray-300 dark:hover:text-white"
                  @click="inspect(message.message_id)">
                  {{ t('web.admin.jobs.retry') }}
                </button>
              </div>
              <template v-else-if="inspectRecord">
                <template v-if="!inspectRecord.found || !inspectMessage">
                  <p
                    class="text-xs text-amber-800 dark:text-amber-300"
                    data-testid="dlq-inspect-not-visible">
                    {{ t('web.admin.jobs.dlq.notVisible', { scanned: inspectRecord.scanned }) }}
                  </p>
                  <template v-if="inspectRecord.truncated">
                    <p
                      class="mt-1 text-xs text-amber-800 dark:text-amber-300"
                      data-testid="dlq-inspect-truncated">
                      {{ t('web.admin.jobs.dlq.truncated', { scanned: inspectRecord.scanned }) }}
                    </p>
                    <code
                      class="mt-1 block font-mono text-xs break-all text-gray-900 dark:text-gray-100"
                      data-testid="dlq-inspect-deep-scan">
                      {{ dlqDeepScanCommand(selectedShort, message.message_id) }}
                    </code>
                  </template>
                </template>
                <JsonViewer
                  v-else
                  :data="inspectMessage"
                  :expand-depth="2"
                  testid="dlq-inspect-json" />
              </template>
            </div>
          </li>
        </ul>
      </div>
      <!-- Typed-confirmation gate: replay (default) / discard (danger). The
           token is the short queue name — the same string as the URL segment.

           NESTED IN THE DRAWER ON PURPOSE. headlessui only treats a dialog as
           a child when it is rendered inside the parent dialog's subtree.
           A sibling dialog is "outside" the drawer, so the drawer closes on the
           first click into it: the queue is deselected, the re-peek goes to
           an empty queue name and the LAST ACTION panel above is never seen. -->
      <AdminConfirmDialog
        v-model:open="actionDialogOpen"
        :title="t(`web.admin.jobs.dlq.${actionVerb}.confirmTitle`)"
        :description="
          t(`web.admin.jobs.dlq.${actionVerb}.confirmDescription`, {
            id: actionMessageId,
            queue: actionQueueFull,
          })
        "
        :confirm-token="actionQueue"
        :variant="actionVerb === 'discard' ? 'danger' : 'default'"
        :confirm-text="t(`web.admin.jobs.dlq.${actionVerb}.button`)"
        request-reason
        :loading="actionLoading"
        :error="actionError"
        @confirm="onActionConfirm"
        @cancel="onActionCancel" />
    </DetailDrawer>
  </section>
</template>
