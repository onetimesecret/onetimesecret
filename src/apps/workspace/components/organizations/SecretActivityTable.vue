<!-- src/apps/workspace/components/organizations/SecretActivityTable.vue -->

<script setup lang="ts">
import { AUDIT_EVENT_KINDS, type AuditEventKind } from '@/schemas/api/organizations';
import TableSkeleton from '@/shared/components/closet/TableSkeleton.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import EmptyState from '@/shared/components/ui/EmptyState.vue';
import { useOrgAuditEvents } from '@/shared/composables/useOrgAuditEvents';
import { formatDisplayDateTime } from '@/utils/format';
import { useNow } from '@vueuse/core';
import { formatDistance } from 'date-fns';
import { computed, onMounted, onUnmounted, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Secret Activity table (#3637) — renders the org's secret-access audit
 * trail: creations, link/status fetches, reveals, burns and expiries.
 *
 * Owns its own fetching via useOrgAuditEvents: the parent mounts it lazily
 * (v-if per tab), so mounting IS activation. The composable keeps network
 * errors and contract mismatches distinct, and so does this template — a
 * parse failure must never masquerade as the "no activity yet" empty state.
 */
const props = defineProps<{
  orgExtid: string;
}>();

const { t } = useI18n();

const orgExtid = toRef(props, 'orgExtid');

const {
  records,
  actors,
  isLoading,
  error,
  validationError,
  offset,
  total,
  count,
  hasNext,
  hasPrev,
  isCapped,
  fetchPage,
  next,
  prev,
  refresh,
  abort,
} = useOrgAuditEvents(orgExtid);

// Reactive clock so the relative "3 minutes ago" labels refresh on their own
// while the tab stays open. Coarse tick — these labels change on a
// minute/hour scale, not per frame.
const now = useNow({ interval: 30_000 });

/**
 * Kinds with a dedicated i18n label. An unknown future kind falls back to
 * its raw name — the schema admits it on purpose, so the row still renders
 * instead of hiding activity.
 */
const KNOWN_KINDS = new Set<string>(AUDIT_EVENT_KINDS);

/** Decorative icon per kind; unknown kinds get the neutral info glyph. */
const KIND_ICONS: Record<AuditEventKind, string> = {
  created: 'plus-circle',
  status_get: 'signal',
  secret_get: 'key',
  previewed: 'eye',
  creator_status_get: 'user-circle',
  receipt_viewed: 'document-text',
  revealed: 'lock-open',
  burned: 'fire',
  expired: 'clock',
  orphaned: 'question-mark-circle',
  reveal_failed_undecryptable: 'exclamation-triangle',
};

/**
 * Actor values events carry (RECOGNIZED_ACTORS, access_timeline.rb);
 * 'system' = expired/orphaned, 'unknown' = the ADR-023 sentinel for an actor
 * whose relationship to the secret could not be established (rendered as an
 * explicit "Unknown", never a blank or a misleading label).
 */
const KNOWN_ACTORS = new Set(['creator', 'authenticated_other', 'anonymous', 'system', 'unknown']);

const kindLabel = (kind: string): string =>
  KNOWN_KINDS.has(kind) ? t(`web.organizations.audit.kinds.${kind}`) : kind;

const kindIcon = (kind: string): string =>
  KIND_ICONS[kind as AuditEventKind] ?? 'information-circle';

const actorLabel = (actor: string): string =>
  KNOWN_ACTORS.has(actor) ? t(`web.organizations.audit.actors.${actor}`) : actor;

/**
 * Rows decorated with their display fields, resolved once per row. Relative
 * times are computed against the reactive clock so they refresh on the tick
 * (formatDistance with an explicit base = formatDistanceToNow, but with a
 * real reactive dependency instead of a hidden Date.now()).
 */
const decoratedEvents = computed(() =>
  records.value.map((event) => ({
    event,
    key: `${event.at.getTime()}-${event.nonce}`,
    label: kindLabel(event.kind),
    icon: kindIcon(event.kind),
    absolute: formatDisplayDateTime(event.at),
    relative: formatDistance(event.at, now.value, { addSuffix: true }),
    actorLabel: event.actor ? actorLabel(event.actor) : null,
    // Read-time identity resolution: email when the full actor objid resolves
    // to a current active member, else the bare objid — unique-but-unresolved
    // (removed member / out-of-org actor), CloudTrail deleted-principal
    // semantics. Email never lives in the trail itself (GDPR minimization).
    actorIdentity: event.actor_id
      ? (actors.value[event.actor_id]?.email ?? event.actor_id)
      : null,
  }))
);

// "Showing X–Y of Z" — 1-based, from the server-echoed clamped offset.
const rangeFrom = computed(() => (count.value === 0 ? 0 : offset.value + 1));
const rangeTo = computed(() => offset.value + count.value);

/**
 * Skeleton only for the very first fetch of a context (mount or org switch),
 * when there is nothing meaningful on screen yet. Pagination and retry keep
 * their current state mounted while the request is in flight: unmounting the
 * subtree would drop keyboard focus from the Prev/Next/Retry button that
 * triggered the fetch and destroy the role="log" live region, defeating its
 * announcements (#3637 a11y review).
 */
const showSkeleton = computed(
  () =>
    isLoading.value && records.value.length === 0 && !error.value && !validationError.value
);

onMounted(() => fetchPage(0));

// Tab switch / navigation unmounts the component mid-fetch; drop the request
// so its response can't resolve into a dead component tree.
onUnmounted(abort);

// Org switch via URL navigation reuses the component — restart at page 1.
// Clearing records first routes the fresh context through the skeleton
// instead of showing the previous org's rows while the new page loads.
// Errors and actors reset too: a latched error/mismatch from the previous
// org would otherwise suppress the skeleton (its gate requires both clear)
// and render the old org's failure banner over the new org's first fetch.
// Paging state likewise: if the new org's first fetch fails, Retry replays
// offset.value — a stale offset would land mid-trail in the new org.
watch(orgExtid, () => {
  records.value = [];
  actors.value = {};
  error.value = null;
  validationError.value = false;
  offset.value = 0;
  total.value = 0;
  fetchPage(0);
});
</script>

<template>
  <div>
    <!-- Loading State — initial fetch only; refetches keep their state mounted -->
    <TableSkeleton v-if="showSkeleton" />

    <!-- Network/HTTP Error State -->
    <div
      v-else-if="error"
      data-testid="org-audit-error"
      class="flex items-start gap-3 rounded-md bg-red-50 p-4 dark:bg-red-900/20">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        class="mt-0.5 size-5 shrink-0 text-red-500 dark:text-red-400"
        aria-hidden="true" />
      <div class="flex-1 text-sm text-red-700 dark:text-red-300">
        <p>{{ t('web.organizations.audit.load_error') }}</p>
        <p class="mt-1 text-xs text-red-600 dark:text-red-400">{{ error }}</p>
      </div>
      <button
        type="button"
        @click="refresh"
        class="shrink-0 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-red-700 shadow-sm ring-1 ring-red-300 ring-inset hover:bg-red-50 dark:bg-transparent dark:text-red-300 dark:ring-red-700 dark:hover:bg-red-900/30">
        {{ t('web.organizations.audit.retry') }}
      </button>
    </div>

    <!--
      Contract-Mismatch State — the response arrived but failed validation.
      Rendered as its own state, never as the empty state: on an audit log an
      empty list born from a parse failure is the worst possible lie.
    -->
    <div
      v-else-if="validationError"
      data-testid="org-audit-contract-mismatch"
      class="flex items-start gap-3 rounded-md bg-amber-50 p-4 dark:bg-amber-900/20">
      <OIcon
        collection="heroicons"
        name="shield-exclamation"
        class="mt-0.5 size-5 shrink-0 text-amber-500 dark:text-amber-400"
        aria-hidden="true" />
      <p class="flex-1 text-sm text-amber-700 dark:text-amber-300">
        {{ t('web.organizations.audit.contract_mismatch') }}
      </p>
      <button
        type="button"
        @click="refresh"
        class="shrink-0 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-amber-700 shadow-sm ring-1 ring-amber-300 ring-inset hover:bg-amber-50 dark:bg-transparent dark:text-amber-300 dark:ring-amber-700 dark:hover:bg-amber-900/30">
        {{ t('web.organizations.audit.retry') }}
      </button>
    </div>

    <!-- Empty State -->
    <EmptyState
      v-else-if="records.length === 0"
      :show-action="false"
      testid="org-audit-empty">
      <template #title>
        {{ t('web.organizations.audit.empty_title') }}
      </template>
      <template #description>
        {{ t('web.organizations.audit.empty_description') }}
      </template>
    </EmptyState>

    <!-- Event List -->
    <div v-else>
      <!-- Retention-cap notice — the trail keeps only the newest 10,000 events -->
      <div
        v-if="isCapped"
        data-testid="org-audit-capped"
        class="mb-4 flex items-center gap-2 rounded-md bg-gray-50 px-4 py-2.5 text-xs text-gray-600 dark:bg-gray-700/50 dark:text-gray-400">
        <OIcon
          collection="heroicons"
          name="information-circle"
          class="size-4 shrink-0"
          aria-hidden="true" />
        {{ t('web.organizations.audit.capped_notice') }}
      </div>

      <!--
        role="log" + aria-live="polite": the wrapper (not the table) carries
        the log semantics so screen readers announce newly loaded pages while
        the table inside keeps its native table role for cell navigation. The
        region stays mounted across page fetches (only the rows change) so the
        live-region announcement actually fires; in-flight fetches dim it and
        flag aria-busy instead of swapping it out.
      -->
      <div
        role="log"
        aria-live="polite"
        :aria-busy="isLoading"
        :aria-label="t('web.organizations.audit.title')"
        class="overflow-x-auto rounded-lg border border-gray-200 transition-opacity dark:border-gray-700"
        :class="{ 'opacity-60': isLoading }">
        <table
          data-testid="org-audit-table"
          class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 font-brand dark:bg-gray-800">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.audit.columns.event') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.audit.columns.secret') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.audit.columns.actor') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.audit.columns.when') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-800/50">
            <tr
              v-for="{ event, key, label, icon, absolute, relative, actorLabel: rowActor, actorIdentity } in decoratedEvents"
              :key="key"
              data-testid="org-audit-row">
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="flex items-center gap-2">
                  <OIcon
                    collection="heroicons"
                    :name="icon"
                    class="size-5 shrink-0 text-gray-400 dark:text-gray-500"
                    aria-hidden="true" />
                  <span class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ label }}
                  </span>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="font-mono text-sm text-gray-900 dark:text-white">
                  {{ event.secret ?? '—' }}
                </div>
                <div
                  v-if="event.receipt"
                  class="font-mono text-xs text-gray-500 dark:text-gray-400">
                  {{ event.receipt }}
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-700 dark:text-gray-300">
                <template v-if="rowActor">
                  {{ rowActor }}
                  <!-- title carries the full value: full objids overflow the
                       truncated chip, and a resolved email hides the objid -->
                  <span
                    v-if="actorIdentity"
                    :title="actorIdentity"
                    class="ml-1 inline-block max-w-48 truncate align-bottom font-mono text-xs text-gray-500 dark:text-gray-400">
                    {{ actorIdentity }}
                  </span>
                </template>
                <span v-else class="text-gray-400 dark:text-gray-500">—</span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <time
                  :datetime="event.at.toISOString()"
                  class="block text-sm text-gray-700 dark:text-gray-300">
                  {{ absolute }}
                </time>
                <span class="text-xs text-gray-500 dark:text-gray-400">
                  {{ relative }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!--
        Pagination. Buttons are disabled by page bounds only — NOT by
        isLoading: disabling the focused button mid-fetch ejects keyboard
        focus to <body>. Rapid re-clicks are safe because fetchPage aborts
        any in-flight request before issuing the next one.
      -->
      <div class="mt-4 flex items-center justify-between">
        <p class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.audit.showing_range', { from: rangeFrom, to: rangeTo, total }) }}
        </p>
        <div class="flex gap-2">
          <button
            type="button"
            data-testid="org-audit-prev"
            :disabled="!hasPrev"
            @click="prev"
            class="inline-flex items-center gap-1 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            <OIcon
              collection="heroicons"
              name="chevron-left"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.COMMON.previous') }}
          </button>
          <button
            type="button"
            data-testid="org-audit-next"
            :disabled="!hasNext"
            @click="next"
            class="inline-flex items-center gap-1 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            {{ t('web.COMMON.next') }}
            <OIcon
              collection="heroicons"
              name="chevron-right"
              class="size-4"
              aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
