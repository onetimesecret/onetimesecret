// src/schemas/api/internal/responses/colonel-domaintoolbox.ts
//
// Per-resource colonel/admin schemas for the Domain Toolbox (ticket #43).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts and the
// Phase-2 verify schemas in ./colonel-domains.ts are UNTOUCHED (the Zod
// tripwire, epic non-goal). This toolbox surfaces the CLI-only domain toolbox
// (`bin/ots domains {orphaned,probe,repair,transfer}`) — there was no old colonel
// screen for these verbs. Distinct `domaintoolbox` namespace so it never collides
// with Slice-4's colonel-domains.ts.
//
// Shapes verified against the live colonel logic classes
// (apps/api/colonel/logic/colonel/{list_orphaned_domains,probe_domain,
// repair_domain,transfer_domain}.rb), thin adapters over
// Onetime::Operations::Domains::{OrphanedScan,Probe,Repair,Transfer}.
//
// The domain re-verify action is NOT redefined here — it REUSES the existing
// colonel-domains.ts verify schemas + `/api/colonel/domains/:extid/verify`
// endpoint (CONTRACT 3 — reuse over duplication).

import { createApiResponseSchema } from '@/schemas/api/base';
import { paginationSchema } from './colonel';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ============================================================================
// OrphanedScan — GET /api/colonel/domains/orphaned
// ============================================================================

/**
 * One orphaned-domain summary row (a domain with no owning organization).
 * `created` arrives as a Unix-epoch number and is coerced to Date (nullable).
 */
export const colonelOrphanedDomainSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
  verification_state: z.string(),
  verified: z.boolean(),
  created: transforms.fromNumber.toDateNullable,
});

/** Orphaned-scan response details: rows + the shared pagination envelope. */
export const colonelOrphanedDomainsDetailsSchema = z.object({
  domains: z.array(colonelOrphanedDomainSchema),
  pagination: paginationSchema,
});

// ============================================================================
// Probe — GET /api/colonel/domains/:extid/probe
// ============================================================================

/**
 * The HTTP arm of a probe. On a successful connection `status_code` /
 * `status_message` / `success` are present; on a network/SSL failure `error` /
 * `message` are present instead. All optional so both branches parse.
 */
export const colonelDomainProbeHttpSchema = z.object({
  status_code: z.number().optional(),
  status_message: z.string().optional(),
  success: z.boolean().optional(),
  error: z.string().optional(),
  message: z.string().optional(),
});

/**
 * The TLS-certificate arm of a probe. Present only when the connection was
 * established far enough to read a cert; nullable + every field optional so the
 * error branches (no cert, SSL error) parse cleanly.
 */
export const colonelDomainProbeSslSchema = z
  .object({
    valid: z.boolean().optional(),
    subject: z.string().optional(),
    issuer: z.string().optional(),
    not_before: z.string().optional(),
    not_after: z.string().optional(),
    days_until_expiry: z.number().optional(),
    expired: z.boolean().optional(),
    not_yet_valid: z.boolean().optional(),
    error: z.string().optional(),
  })
  .nullable();

/** Probe `record`: the resolved domain's public identity. */
export const colonelDomainProbeRecordSchema = z.object({
  extid: z.string(),
  display_domain: z.string(),
});

/**
 * Probe `details`: the probe result. `health` is the op's honest classification
 * (healthy / ssl_expired / dns_error / timeout / …). `ssl` is optional because
 * some failure branches (connection refused/reset, timeout) never reach a cert.
 */
export const colonelDomainProbeDetailsSchema = z.object({
  timestamp: z.string(),
  domain: z.string(),
  url: z.string(),
  http: colonelDomainProbeHttpSchema,
  ssl: colonelDomainProbeSslSchema.optional(),
  health: z.string(),
});

// ============================================================================
// Repair — POST /api/colonel/domains/:extid/repair
// ============================================================================

/** Repair `record`: the target domain's identity. */
export const colonelDomainRepairRecordSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
});

/**
 * Repair `details`. `status` is the op's outcome symbol as a string
 * (no_issues / needs_org / org_not_found / planned / repaired). `issues` lists
 * the relationship problems found; `repairs_applied` lists what was fixed (empty
 * on a dry-run preview). `dry_run` echoes whether this was a preview.
 */
export const colonelDomainRepairDetailsSchema = z.object({
  status: z.string(),
  dry_run: z.boolean(),
  issues: z.array(z.string()),
  repairs_applied: z.array(z.string()),
});

// ============================================================================
// Transfer — POST /api/colonel/domains/:extid/transfer
// ============================================================================

/** Transfer `record`: the target domain's identity. */
export const colonelDomainTransferRecordSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
});

/**
 * Transfer `details`. `status` is the op outcome string (planned / transferred /
 * mismatch). from/to org ids are strings ('' when orphaned); org names are
 * nullable (an org may carry no display name).
 */
export const colonelDomainTransferDetailsSchema = z.object({
  status: z.string(),
  dry_run: z.boolean(),
  from_org_id: z.string(),
  from_org_name: z.string().nullable(),
  to_org_id: z.string(),
  to_org_name: z.string().nullable(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelOrphanedDomain = z.infer<typeof colonelOrphanedDomainSchema>;
export type ColonelDomainProbeRecord = z.infer<typeof colonelDomainProbeRecordSchema>;
export type ColonelDomainProbeDetails = z.infer<typeof colonelDomainProbeDetailsSchema>;
export type ColonelDomainRepairDetails = z.infer<typeof colonelDomainRepairDetailsSchema>;
export type ColonelDomainTransferDetails = z.infer<typeof colonelDomainTransferDetailsSchema>;

// Wrapped response schemas for the colonel Domain Toolbox (ticket #43).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import these DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions. Distinct `domaintoolbox` namespace — does NOT touch
// Slice-4's colonel-domains.ts.
//
// The re-verify action REUSES colonelDomainVerifyResponseSchema from
// ./colonel-domains (not redefined here).

// GET /api/colonel/domains/orphaned → ListOrphanedDomains
export const colonelDomainsOrphanedResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelOrphanedDomainsDetailsSchema
);

// GET /api/colonel/domains/:extid/probe → ProbeDomain
export const colonelDomainProbeResponseSchema = createApiResponseSchema(
  colonelDomainProbeRecordSchema,
  colonelDomainProbeDetailsSchema
);

// POST /api/colonel/domains/:extid/repair → RepairDomain
export const colonelDomainRepairResponseSchema = createApiResponseSchema(
  colonelDomainRepairRecordSchema,
  colonelDomainRepairDetailsSchema
);

// POST /api/colonel/domains/:extid/transfer → TransferDomain
export const colonelDomainTransferResponseSchema = createApiResponseSchema(
  colonelDomainTransferRecordSchema,
  colonelDomainTransferDetailsSchema
);

export type ColonelDomainsOrphanedResponse = z.infer<typeof colonelDomainsOrphanedResponseSchema>;
export type ColonelDomainProbeResponse = z.infer<typeof colonelDomainProbeResponseSchema>;
export type ColonelDomainRepairResponse = z.infer<typeof colonelDomainRepairResponseSchema>;
export type ColonelDomainTransferResponse = z.infer<typeof colonelDomainTransferResponseSchema>;
