// src/apps/admin/stores/useColonelAuditLog.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelAuditEventsResponseSchema } from '@/schemas/api/internal/responses/colonel-audit';
import type { ColonelAuditEvent } from '@/schemas/api/internal/responses/colonel-audit';

type ColonelAuditEventsResponse = z.infer<typeof colonelAuditEventsResponseSchema>;

/** Server-side filters the audit endpoint supports. */
export interface ColonelAuditFilters {
  /** Case-insensitive substring over the acting colonel's extid/email. */
  actor?: string;
  /** Exact action (`customer.set_role`) or category prefix (`customer`). */
  verb?: string;
}

/** Serialisations `GET /api/colonel/audit/export` can return. */
export type ColonelAuditExportFormat = 'csv' | 'ndjson';

/**
 * Per-resource admin store for the audit log (observability lane, CONTRACT 3).
 *
 * Sibling of {@link useAdminSessions}: one server page per request over the
 * NEW `GET /api/colonel/audit` endpoint — the read side of the ColonelAuditEvent
 * flight recorder every mutating admin op writes into. The endpoint supports
 * server-side `actor` / `verb` filters; the view drives them through
 * {@link fetchPage}. Reading the log never writes an audit event (CONTRACT 4).
 * ZERO import edge into `src/apps/colonel/*` or `colonelInfoStore`.
 */
export const useColonelAuditLog = defineStore('colonelAuditLog', () => {
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
    filters?: ColonelAuditFilters
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

  /**
   * URL for a full download of the trail under the given filters.
   *
   * NOT fetched through {@link pager} or any schema: the endpoint answers with
   * `text/csv` / `application/x-ndjson` plus a `Content-Disposition` attachment
   * header, so it is navigated to, not parsed. There is deliberately no Zod
   * shape for a non-JSON body (see the note in
   * `@/schemas/api/internal/responses/colonel-audit`); the FIELDS it serialises
   * are the same allowlist `colonelAuditEventSchema` types, enforced
   * server-side by one shared reader.
   *
   * The export covers the whole retained trail under the current filters, not
   * the current page — pagination is a screen concern, an export is not.
   */
  function exportUrl(format: ColonelAuditExportFormat, filters?: ColonelAuditFilters): string {
    const query = new URLSearchParams({ format });
    if (filters?.actor) query.set('actor', filters.actor);
    if (filters?.verb) query.set('verb', filters.verb);
    return `/api/colonel/audit/export?${query.toString()}`;
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
    exportUrl,
    $reset,
  };
});
