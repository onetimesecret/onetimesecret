// src/shared/composables/useOrgAuditEvents.ts

/**
 * Offset/limit pager over GET /api/organizations/:extid/audit-events — the
 * org's secret-access audit trail (#3637).
 *
 * `error` and `validationError` are deliberately kept apart and must NOT
 * collapse into one state:
 *
 *   - error           the request threw (network/HTTP) → error banner + retry.
 *   - validationError the response ARRIVED but failed Zod. Degrading that to
 *                     an empty list would render as the ordinary "no activity
 *                     yet" empty state — on an audit log that is the worst
 *                     possible lie: a broken read contract reads as "nobody
 *                     touched anything". Callers must render it as its own
 *                     contract-mismatch state.
 *
 * They are mutually exclusive by construction — every fetch OUTCOME sets
 * exactly one and clears the other. Deliberately NOT cleared on fetch entry:
 * the current state (error banner, mismatch notice) must stay mounted while a
 * retry is in flight, so the Retry button keeps keyboard focus instead of
 * being unmounted the instant it is clicked (#3637 a11y review).
 */

import {
  auditEventsResponseSchema,
  type AuditActorsMap,
  type OrgAuditEvent,
} from '@/schemas/api/organizations';
import { classifyError } from '@/schemas/errors';
import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';
import { computed, ref, type Ref } from 'vue';

/** Server default page size (list_audit_events.rb DEFAULT_LIMIT). */
const DEFAULT_LIMIT = 50;

/**
 * Per-org retention cap (audit_trail.rb AUDIT_EVENTS_MAX). When `total`
 * saturates here the trail has been trimmed — older events are gone and the
 * UI should say so rather than imply a complete history.
 */
const AUDIT_EVENTS_RETENTION_MAX = 10_000;

/* eslint-disable max-lines-per-function */
export function useOrgAuditEvents(orgExtid: Ref<string>) {
  const $api = useApi();

  const records = ref<OrgAuditEvent[]>([]);
  /**
   * Read-time identity resolution for the current page (details.actors),
   * keyed by full actor objid. Missing key = unresolved actor (removed
   * member / out-of-org) — callers render the bare objid. Defaults to {}
   * so older backend responses without the map still work.
   */
  const actors = ref<AuditActorsMap>({});
  const isLoading = ref(false);
  /** Network/HTTP failure message; null when the last fetch succeeded. */
  const error = ref<string | null>(null);
  /** True when the response arrived but failed schema validation. */
  const validationError = ref(false);
  const offset = ref(0);
  const limit = ref(DEFAULT_LIMIT);
  const total = ref(0);

  let abortController: AbortController | null = null;

  const count = computed(() => records.value.length);
  const hasNext = computed(() => offset.value + count.value < total.value);
  const hasPrev = computed(() => offset.value > 0);
  const isCapped = computed(() => total.value >= AUDIT_EVENTS_RETENTION_MAX);

  /** Abort the in-flight request, if any. */
  function abort() {
    if (abortController) {
      abortController.abort();
      abortController = null;
    }
  }

  /**
   * Fetch one page at `targetOffset`. Aborts any in-flight request first so
   * rapid paging can't interleave stale responses.
   */
  async function fetchPage(targetOffset: number = offset.value): Promise<void> {
    abort();
    const controller = new AbortController();
    abortController = controller;
    isLoading.value = true;

    try {
      const response = await $api.get(`/api/organizations/${orgExtid.value}/audit-events`, {
        params: { offset: Math.max(0, targetOffset), limit: limit.value },
        signal: controller.signal,
      });

      const result = gracefulParse(auditEventsResponseSchema, response.data, 'AuditEventsResponse');
      if (!result.ok) {
        // Contract mismatch: do NOT degrade to an empty list (see header note).
        records.value = [];
        actors.value = {};
        validationError.value = true;
        error.value = null;
        return;
      }

      records.value = result.data.records;
      actors.value = result.data.details.actors ?? {};
      total.value = result.data.total;
      // Echo the server's clamped paging values so the range display and
      // next/prev math always agree with what was actually returned.
      offset.value = result.data.details.offset;
      limit.value = result.data.details.limit;
      error.value = null;
      validationError.value = false;
    } catch (err) {
      // A superseded request aborting is not an error state.
      if (controller.signal.aborted) return;
      const classified = classifyError(err);
      error.value = classified.message;
      validationError.value = false;
    } finally {
      if (abortController === controller) {
        abortController = null;
        isLoading.value = false;
      }
    }
  }

  const next = () => fetchPage(offset.value + limit.value);
  const prev = () => fetchPage(Math.max(0, offset.value - limit.value));
  const refresh = () => fetchPage(offset.value);

  return {
    // State
    records,
    actors,
    isLoading,
    error,
    validationError,
    offset,
    limit,
    total,
    count,

    // Derived
    hasNext,
    hasPrev,
    isCapped,

    // Actions
    fetchPage,
    next,
    prev,
    refresh,
    abort,
  };
}
