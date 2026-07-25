// src/apps/admin/stores/useAdminDomains.ts

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { createApiResponseSchema } from '@/schemas/api/base';
import type { ColonelCustomDomain } from '@/schemas/api/internal/responses/colonel';
import { colonelCustomDomainsResponseSchema } from '@/schemas/api/internal/responses/colonel';
import {
  colonelDomainDetailResponseSchema,
  colonelDomainVerifyResponseSchema,
  type ColonelDomainCluster,
  type ColonelDomainDetailRecord,
  type ColonelDomainVerifyDetails,
} from '@/schemas/api/internal/responses/colonel-domains';
import {
  colonelDomainProbeResponseSchema,
  colonelDomainRepairResponseSchema,
  colonelDomainTransferResponseSchema,
  type ColonelDomainProbeDetails,
  type ColonelDomainRepairDetails,
  type ColonelDomainTransferDetails,
} from '@/schemas/api/internal/responses/colonel-domaintoolbox';
import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';
import type { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { ref } from 'vue';
import { z } from 'zod';

type ColonelCustomDomainsResponse = z.infer<typeof colonelCustomDomainsResponseSchema>;

// ---------------------------------------------------------------------------
// Remove ack (DELETE /api/colonel/domains/:extid)
//
// TEMPORARY HOME. Every other colonel domain schema lives in
// `src/schemas/api/internal/responses/colonel-domains.ts`; this one is declared
// here because that file is owned by another workstream in the current split.
// Move it there verbatim (and re-export from this module) when the contract
// files are next touched — nothing else needs to change.
//
// Shape verified against ColonelAPI::Logic::Colonel::RemoveCustomDomain
// #success_data. `display_domain` is nullable because the applied path snapshots
// it from the op result AFTER destroy! has nil'd the in-memory attribute.
// ---------------------------------------------------------------------------

export const colonelDomainRemoveRecordSchema = z.object({
  deleted: z.boolean(),
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string().nullable(),
});

/**
 * Remove outcome. `status` is the op's symbol as a string (planned / removed /
 * not_found); `dry_run` echoes whether this was a PREVIEW — the endpoint
 * defaults it to TRUE, so a plain DELETE never destroys anything.
 * `reasserts_survivor` is true when tearing this record down hands the
 * display_domain index back to another CustomDomain row.
 */
export const colonelDomainRemoveDetailsSchema = z.object({
  status: z.string(),
  dry_run: z.boolean(),
  org_id: z.string(),
  org_name: z.string().nullable(),
  reasserts_survivor: z.boolean(),
});

export const colonelDomainRemoveResponseSchema = createApiResponseSchema(
  colonelDomainRemoveRecordSchema,
  colonelDomainRemoveDetailsSchema
);

export type ColonelDomainRemoveDetails = z.infer<typeof colonelDomainRemoveDetailsSchema>;

/**
 * Server-side filters `GET /api/colonel/domains` accepts. All are AND-ed and
 * applied BEFORE pagination, so `total_count` reflects the filtered set.
 * `search` is a case-insensitive substring over display_domain / base_domain
 * plus an exact extid / domain_id match — it does NOT match the org name.
 */
export interface DomainListFilters {
  search?: string;
  /** Exact verification_state ('verified' | 'resolving' | 'pending'). */
  status?: string;
  /** Owning organization, by extid or objid. */
  orgId?: string;
}

/** The `{ record, cluster }` pair every domain detail read resolves to. */
export interface ColonelDomainDetail {
  record: ColonelDomainDetailRecord;
  cluster: ColonelDomainCluster;
}

/** Options for the repair verb. `dryRun` is explicit — never defaulted here. */
export interface DomainRepairOptions {
  /** Target org for the ORPHANED case (objid or extid). Omitted when blank. */
  orgId?: string;
  dryRun: boolean;
}

/** Options for the transfer verb. `dryRun` is explicit — never defaulted here. */
export interface DomainTransferOptions {
  /** REQUIRED destination org (objid or extid). */
  toOrg: string;
  /** Optional ownership assertion; a mismatch is a 4xx on field `from_org`. */
  fromOrg?: string;
  dryRun: boolean;
}

// ---------------------------------------------------------------------------
// Per-domain operations.
//
// Module-level so each verb stays small and independently readable; the store
// binds them to the injected Axios instance below. Every one THROWS on a
// network/HTTP failure (so the caller's useAdminMutation can classify it into
// the confirm dialog) and resolves `null` when a 2xx ack fails its Zod contract
// — the mutation still happened server-side, acks are tripwires, not gates.
// Audit is written SERVER-SIDE by each operation (CONTRACT 4).
// ---------------------------------------------------------------------------

/** Path for a single domain, resolved by PUBLIC id (extid) only. */
function domainPath(extid: string): string {
  return `/api/colonel/domains/${encodeURIComponent(extid)}`;
}

/** Read one domain's full record + the deployment's proxy cluster. READ-ONLY. */
async function fetchDomainDetail(
  $api: AxiosInstance,
  extid: string
): Promise<ColonelDomainDetail | null> {
  const response = await $api.get(domainPath(extid));
  const parsed = gracefulParse(
    colonelDomainDetailResponseSchema,
    response.data,
    'ColonelDomainDetailResponse'
  );
  if (!parsed.ok) return null;
  return { record: parsed.data.record, cluster: parsed.data.details?.cluster ?? null };
}

/**
 * Run DNS + SSL verification. The op reports the REAL post-check state, so the
 * caller must surface `current_state` honestly rather than assuming success.
 */
async function verifyDomain(
  $api: AxiosInstance,
  extid: string
): Promise<ColonelDomainVerifyDetails | null> {
  const response = await $api.post(`${domainPath(extid)}/verify`);
  const parsed = gracefulParse(
    colonelDomainVerifyResponseSchema,
    response.data,
    'ColonelDomainVerifyResponse'
  );
  return parsed.ok ? parsed.data.details ?? null : null;
}

/**
 * HTTPS + TLS diagnostics for a domain. READ-ONLY (no audit); the server clamps
 * `timeout` to 1..30s.
 */
async function probeDomain(
  $api: AxiosInstance,
  extid: string,
  timeout?: number
): Promise<ColonelDomainProbeDetails | null> {
  const response = await $api.get(
    `${domainPath(extid)}/probe`,
    timeout ? { params: { timeout } } : undefined
  );
  const parsed = gracefulParse(
    colonelDomainProbeResponseSchema,
    response.data,
    'ColonelDomainProbeResponse'
  );
  return parsed.ok ? parsed.data.details ?? null : null;
}

/**
 * Repair a domain's organization relationship. `dryRun: true` PREVIEWS
 * (`repairs_applied` stays empty); `dryRun: false` applies and audits.
 */
async function repairDomain(
  $api: AxiosInstance,
  extid: string,
  options: DomainRepairOptions
): Promise<ColonelDomainRepairDetails | null> {
  const body: Record<string, unknown> = { dry_run: options.dryRun };
  if (options.orgId) body.org_id = options.orgId;

  const response = await $api.post(`${domainPath(extid)}/repair`, body);
  const parsed = gracefulParse(
    colonelDomainRepairResponseSchema,
    response.data,
    'ColonelDomainRepairResponse'
  );
  return parsed.ok ? parsed.data.details ?? null : null;
}

/**
 * Move a domain to another organization. `dryRun: true` PREVIEWS the move;
 * `dryRun: false` applies and audits. A `fromOrg` mismatch is a 4xx.
 */
async function transferDomain(
  $api: AxiosInstance,
  extid: string,
  options: DomainTransferOptions
): Promise<ColonelDomainTransferDetails | null> {
  const body: Record<string, unknown> = {
    dry_run: options.dryRun,
    to_org: options.toOrg,
  };
  if (options.fromOrg) body.from_org = options.fromOrg;

  const response = await $api.post(`${domainPath(extid)}/transfer`, body);
  const parsed = gracefulParse(
    colonelDomainTransferResponseSchema,
    response.data,
    'ColonelDomainTransferResponse'
  );
  return parsed.ok ? parsed.data.details ?? null : null;
}

/**
 * Permanently delete a domain.
 *
 * `dry_run` rides the QUERY STRING (not a request body): DELETE bodies are not
 * reliably parsed across the stack, and the endpoint defaults `dry_run` to TRUE
 * — so an apply MUST send `dry_run=false` explicitly. Always check
 * `details.dry_run` on the response before reporting a removal.
 */
async function removeDomain(
  $api: AxiosInstance,
  extid: string,
  dryRun: boolean
): Promise<ColonelDomainRemoveDetails | null> {
  const response = await $api.delete(`${domainPath(extid)}?dry_run=${dryRun}`);
  const parsed = gracefulParse(
    colonelDomainRemoveResponseSchema,
    response.data,
    'ColonelDomainRemoveResponse'
  );
  return parsed.ok ? parsed.data.details ?? null : null;
}

/** Bind every per-domain verb to one Axios instance for the store's surface. */
function bindOperations($api: AxiosInstance) {
  return {
    fetchDetail: (extid: string) => fetchDomainDetail($api, extid),
    verify: (extid: string) => verifyDomain($api, extid),
    probe: (extid: string, timeout?: number) => probeDomain($api, extid, timeout),
    repair: (extid: string, options: DomainRepairOptions) =>
      repairDomain($api, extid, options),
    transfer: (extid: string, options: DomainTransferOptions) =>
      transferDomain($api, extid, options),
    remove: (extid: string, dryRun: boolean) => removeDomain($api, extid, dryRun),
  };
}

/**
 * Per-resource admin store for custom domains (CONTRACT 1 / #31).
 *
 * Two responsibilities:
 *
 * 1. LIST paging over `GET /api/colonel/domains` via the shared
 *    {@link usePaginatedFetch} composable — one server page per request, never
 *    load-all-then-slice — with the endpoint's server-side filters.
 * 2. The per-domain OPERATIONS both domain screens share (verify, probe,
 *    repair, transfer, remove, detail read). They live here, not in a view, so
 *    the list, the detail page and the Domain Toolbox drive the SAME endpoints
 *    with the same ack parsing instead of three divergent copies.
 *
 * Isolation: ZERO import edge into `src/apps/colonel/*` or
 * `src/shared/stores/colonelInfoStore.ts` (enforced by the architecture test),
 * so the legacy tree never enters the isolated admin bundle.
 */
export const useAdminDomains = defineStore('adminDomains', () => {
  const operations = bindOperations(useApi());

  /** Rows for the current page only (one server page — never accumulated). */
  const domains = ref<ColonelCustomDomain[]>([]);
  const pagination = ref<PageMeta | null>(null);

  /**
   * Every list row seen this session, keyed by extid.
   *
   * The detail endpoint (`GET /api/colonel/domains/:extid`) returns the domain's
   * safe_dump, which does NOT carry `org_id` / `org_name` — so the detail page
   * recovers the owning organization from the row it was opened from. Bounded by
   * the pages an operator actually visits and cleared by `$reset()`.
   */
  const rowIndex = ref<Record<string, ColonelCustomDomain>>({});

  const pager = usePaginatedFetch<ColonelCustomDomainsResponse, ColonelCustomDomain>({
    url: '/api/colonel/domains',
    schema: colonelCustomDomainsResponseSchema,
    context: 'CustomDomainsResponse',
    select: (data) => ({
      items: data.details?.domains ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /** The cached list row for `extid`, or null when it was never listed here. */
  function rowFor(extid: string): ColonelCustomDomain | null {
    return rowIndex.value[extid] ?? null;
  }

  /**
   * Fetch one page of domains.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param filters server-side filters; empty values are dropped by the pager.
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    filters?: DomainListFilters
  ): Promise<{ items: ColonelCustomDomain[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage, {
        search: filters?.search,
        status: filters?.status,
        org_id: filters?.orgId,
      });
      if (result) {
        domains.value = result.items;
        pagination.value = result.pagination;
        for (const row of result.items) rowIndex.value[row.extid] = row;
      } else {
        domains.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      domains.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Drop a domain from the row cache (e.g. after it was removed). */
  function forget(extid: string): void {
    delete rowIndex.value[extid];
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    domains.value = [];
    pagination.value = null;
    rowIndex.value = {};
    pager.reset();
  }

  return {
    // State
    domains,
    pagination,
    rowIndex,
    // Fetch state (owned by the shared composable)
    loading: pager.loading,
    error: pager.error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    // Actions
    fetchPage,
    rowFor,
    forget,
    $reset,
    ...operations,
  };
});
