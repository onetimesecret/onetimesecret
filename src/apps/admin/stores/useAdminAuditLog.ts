// src/apps/admin/stores/useAdminAuditLog.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelAuditEventsResponseSchema } from '@/schemas/api/internal/responses/colonel-audit';
import type { ColonelAuditEvent } from '@/schemas/api/account/responses/colonel-audit';

type ColonelAuditEventsResponse = z.infer<typeof colonelAuditEventsResponseSchema>;

/** Server-side filters the audit endpoint supports. */
export interface AuditLogFilters {
  /** Case-insensitive substring over the acting colonel's extid/email. */
  actor?: string;
  /** Exact action (`customer.set_role`) or category prefix (`customer`). */
  verb?: string;
}

/**
 * Per-resource admin store for the audit log (observability lane, CONTRACT 3).
 *
 * Sibling of {@link useAdminSessions}: one server page per request over the
 * NEW `GET /api/colonel/audit` endpoint — the read side of the AdminAuditEvent
 * flight recorder every mutating admin op writes into. The endpoint supports
 * server-side `actor` / `verb` filters; the view drives them through
 * {@link fetchPage}. Reading the log never writes an audit event (CONTRACT 4).
 * ZERO import edge into `src/apps/colonel/*` or `colonelInfoStore`.
 */
export const useAdminAuditLog = defineStore('adminAuditLog', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const events = ref<ColonelAuditEvent[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelAuditEventsResponse, ColonelAuditEvent>({
    url: '/api/colonel/audit',
    schema: colonelAuditEventsResponseSchema,
    context: 'ColonelAuditEventsResponse',
    select: (data) => ({
      items: data.details?.events ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of audit events, optionally filtered by actor and/or verb.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param filters optional server-side actor/verb filters.
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    filters?: AuditLogFilters
  ): Promise<{ items: ColonelAuditEvent[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage, {
        actor: filters?.actor,
        verb: filters?.verb,
      });
      if (result) {
        events.value = result.items;
        pagination.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        events.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to handle.
      events.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    events.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    events,
    pagination,
    // Fetch state (owned by the shared composable)
    loading: pager.loading,
    error: pager.error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    // Actions
    fetchPage,
    $reset,
  };
});
