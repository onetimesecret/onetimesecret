// src/apps/admin/stores/useAdminCustomers.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { reasonQueryArgs } from '@/apps/admin/utils/operatorReason';
import {
  colonelUserMutationResponseSchema,
  colonelUsersResponseSchema,
} from '@/schemas/api/internal/responses/colonel';
import type { ColonelUser } from '@/schemas/api/internal/responses/colonel';
import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';

type ColonelUsersResponse = z.infer<typeof colonelUsersResponseSchema>;

/** Single-customer colonel URL, keyed by the row's public id (extid, 'ur…'). */
function userUrl(userId: string): string {
  return `/api/colonel/users/${encodeURIComponent(userId)}`;
}

/**
 * Ack tripwire for the mutation endpoints: reports contract drift without ever
 * failing the action (a 2xx means it already happened server-side).
 */
function parseMutationAck(data: unknown): void {
  gracefulParse(colonelUserMutationResponseSchema, data, 'ColonelUserMutationResponse');
}

/**
 * Replace one row (matched by public id) with a patched copy, so the table cell
 * and any open drawer re-render off the ack instead of waiting for a re-read.
 *
 * @returns the new array plus the patched row, or the array unchanged and a
 *   null row when that customer is not on the current page.
 */
function replaceRow(
  rows: ColonelUser[],
  userId: string,
  patch: Partial<ColonelUser>
): { rows: ColonelUser[]; updated: ColonelUser | null } {
  const index = rows.findIndex((row) => row.user_id === userId);
  if (index === -1) return { rows, updated: null };
  const updated: ColonelUser = { ...rows[index], ...patch };
  return { rows: [...rows.slice(0, index), updated, ...rows.slice(index + 1)], updated };
}

/**
 * Per-resource admin store for customers/users (CONTRACT 3).
 *
 * Backed by the `GET /api/colonel/users` endpoint and
 * `colonelUsersResponseSchema`. The endpoint supports an optional server-side
 * `search` param (email lookup via a bounded index scan) alongside the `role`
 * filter; the view drives both through {@link fetchPage}. Owns ONLY this
 * resource — loading/page/error come from the shared paginated-fetch
 * composable, so adding the next resource is a copy of this ~40-line file, not
 * an edit to a shared god-store.
 *
 * Also owns the two row-scoped operator mutations the list drawer offers
 * ({@link setVerification} and {@link purge}) so the drawer never has to reach
 * for a raw HTTP client: both go through the injected Axios instance, ack-parse
 * as a tripwire, and patch local state so the open drawer reflects the new
 * server state without a page reload. Audit is written SERVER-SIDE by the
 * operation — nothing here logs it.
 *
 * Isolation: this module has ZERO import edge into `src/apps/colonel/*` or
 * `src/shared/stores/colonelInfoStore.ts` (enforced by an architecture test),
 * so it never drags the retiring legacy tree into the admin bundle.
 */
export const useAdminCustomers = defineStore('adminCustomers', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const customers = ref<ColonelUser[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const $api = useApi();

  const pager = usePaginatedFetch<ColonelUsersResponse, ColonelUser>({
    url: '/api/colonel/users',
    schema: colonelUsersResponseSchema,
    context: 'ColonelUsersResponse',
    select: (data) => ({
      items: data.details?.users ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of customers.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param roleFilter optional `role` server filter (e.g. 'colonel').
   * @param search optional email search term (server-side, bounded index scan).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    roleFilter?: string,
    search?: string
  ): Promise<{ items: ColonelUser[]; pagination: PageMeta | null } | null> {
    try {
      // Empty/undefined params are dropped by the pager, so both filters can be
      // passed unconditionally.
      const result = await pager.fetchPage(targetPage, { role: roleFilter, search });
      if (result) {
        customers.value = result.items;
        pagination.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        customers.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to handle.
      customers.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /**
   * Manually verify / unverify one account
   * (POST /api/colonel/users/:user_id/verify | /unverify).
   *
   * On a 2xx the row is replaced in place with `verified` flipped, so the open
   * drawer and the table cell both show the new state immediately — no refetch,
   * no page reload. The ack is schema-checked as a live tripwire but never fails
   * the action (a 2xx means it happened server-side).
   *
   * @param userId the customer's public id (extid, 'ur…' — `row.user_id`).
   * @param verified the target state.
   * @returns the patched row, or null when it is not on the current page.
   * @throws the network/HTTP error, for `useAdminMutation` to classify.
   */
  async function setVerification(
    userId: string,
    verified: boolean
  ): Promise<ColonelUser | null> {
    const verb = verified ? 'verify' : 'unverify';
    const response = await $api.post(`${userUrl(userId)}/${verb}`, {});
    parseMutationAck(response.data);
    const patched = replaceRow(customers.value, userId, { verified });
    customers.value = patched.rows;
    return patched.updated;
  }

  /**
   * Purge one account (DELETE /api/colonel/users/:user_id) — irreversible, so
   * the view gates it behind the typed-confirmation dialog.
   *
   * Drops the row ONLY after a 2xx: the drop is sequenced after the awaited
   * DELETE, so a failure throws before it and the row stays. Callers still
   * refetch the page afterwards (totals/pagination move server-side).
   *
   * @param userId the customer's public id (extid, 'ur…').
   * @param reason OPTIONAL operator-supplied why (#4338) — query string, since
   *   this is a DELETE. Omitted entirely when blank.
   * @throws the network/HTTP error, for `useAdminMutation` to classify.
   */
  async function purge(userId: string, reason?: string): Promise<void> {
    const response = await $api.delete(userUrl(userId), ...reasonQueryArgs(reason));
    parseMutationAck(response.data);
    customers.value = customers.value.filter((row) => row.user_id !== userId);
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    customers.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    customers,
    pagination,
    // Fetch state (owned by the shared composable)
    loading: pager.loading,
    error: pager.error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    // Actions
    fetchPage,
    setVerification,
    purge,
    $reset,
  };
});
