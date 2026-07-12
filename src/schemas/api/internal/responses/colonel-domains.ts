// src/schemas/api/internal/responses/colonel-domains.ts

/**
 * Colonel (Admin) domains — NEW verify-endpoint schemas (ticket #31).
 *
 * The domains LIST read side already has frozen schemas
 * (`colonelCustomDomainSchema` / `colonelCustomDomainsResponseSchema` in
 * `./colonel` + `../../internal/responses/colonel`); the domains screen REUSES
 * those (CONTRACT 3 — reuse over duplication). This file adds ONLY the schemas
 * for the NEW `POST /api/colonel/domains/:extid/verify` endpoint, kept in a
 * per-resource file so the domains screen never edits another screen's contract
 * (CONTRACT 2 / the Zod tripwire — new schemas only).
 *
 * These describe the SHAPE the new colonel logic class
 * (`ColonelAPI::Logic::Colonel::VerifyCustomDomain`) returns: the refreshed
 * domain `record` plus the honest verification outcome in `details`. The verify
 * op reports real DNS/SSL state, so `current_state` is authoritative and the
 * screen surfaces it verbatim (verified / resolving / pending / unverified) —
 * it never fakes success.
 */

import { createApiResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Refreshed domain record after a verify. A minimal slice — just what the card
 * needs to re-render its badge/flags without a full list re-fetch. Fields mirror
 * their counterparts on {@link colonelCustomDomainSchema}. `updated` arrives as a
 * Unix-epoch number and is coerced to Date (nullable).
 */
export const colonelDomainVerifyRecordSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
  verification_state: z.string(),
  verified: z.boolean(),
  resolving: z.boolean(),
  ready: z.boolean(),
  updated: transforms.fromNumber.toDateNullable,
});

/**
 * The verify outcome. `current_state` is the post-verification state and drives
 * the operator-facing notification. `error` is the op's captured DNS/SSL error
 * message (or null on a clean run) — surfaced honestly rather than swallowed.
 */
export const colonelDomainVerifyDetailsSchema = z.object({
  previous_state: z.string(),
  current_state: z.string(),
  changed: z.boolean(),
  dns_validated: z.boolean(),
  ssl_ready: z.boolean(),
  is_resolving: z.boolean(),
  error: z.string().nullable(),
  message: z.string(),
});

export type ColonelDomainVerifyRecord = z.infer<typeof colonelDomainVerifyRecordSchema>;
export type ColonelDomainVerifyDetails = z.infer<typeof colonelDomainVerifyDetailsSchema>;

// Wrapped response schema for the NEW colonel domain-verify endpoint (ticket
// #31). Internal-only; consumed by the Vue admin bundle. Per-resource file so
// the domains screen typechecks independently of the shared registry (CONTRACT
// 3) and never touches another screen's contract. The Integrate step adds the
// matching `colonelDomainVerify` key to `registry.ts`.
//
// The domains LIST read schema (`colonelCustomDomainsResponseSchema`) is REUSED
// from `./colonel`, not redefined here.

/** `POST /api/colonel/domains/:extid/verify` → `{ record, details }` ack. */
export const colonelDomainVerifyResponseSchema = createApiResponseSchema(
  colonelDomainVerifyRecordSchema,
  colonelDomainVerifyDetailsSchema
);

export type ColonelDomainVerifyResponse = z.infer<typeof colonelDomainVerifyResponseSchema>;

// ============================================================================
// Colonel create-for-org + per-domain detail (admin "attach domain to org").
//
// `POST /api/colonel/domains` and `GET /api/colonel/domains/:extid` both return
// the full domain `safe_dump` as `record` (a superset of the list projection —
// it carries the DNS-validation fields the operator DNS panel renders) plus the
// deployment's proxy `cluster` in `details`. New per-resource schemas so the
// create/detail flow typechecks independently of the list contract.
//
// DNS-validation fields are declared nullable/optional: the panel degrades to
// "—" for any the dump omits rather than failing the parse (it reads through
// gracefulParse), and unverified/self-hosted domains legitimately lack some.
// ============================================================================

/** Full domain record returned by the colonel create + detail endpoints. */
export const colonelDomainDetailRecordSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
  base_domain: z.string().nullable().optional(),
  subdomain: z.string().nullable().optional(),
  trd: z.string().nullable().optional(),
  tld: z.string().nullable().optional(),
  status: z.string().nullable().optional(),
  verification_state: z.string(),
  verified: z.boolean(),
  resolving: z.boolean(),
  ready: z.boolean(),
  is_apex: z.boolean().nullable().optional(),
  // DNS ownership-validation record the operator must publish.
  txt_validation_host: z.string().nullable().optional(),
  txt_validation_value: z.string().nullable().optional(),
  // Owning organization identity (present on the colonel dump).
  org_id: z.string().nullable().optional(),
  org_name: z.string().nullable().optional(),
  created: transforms.fromNumber.toDateNullable.optional(),
  updated: transforms.fromNumber.toDateNullable.optional(),
});

/**
 * The deployment proxy target the DNS records point at. Shape mirrors
 * `Onetime::DomainValidation::Features.safe_dump`; kept permissive
 * (`passthrough`) so an added proxy field never trips the parse.
 */
export const colonelDomainClusterSchema = z
  .object({
    proxy_ip: z.string().nullable().optional(),
    proxy_host: z.string().nullable().optional(),
  })
  .passthrough()
  .nullable();

export const colonelDomainDetailsSchema = z.object({
  cluster: colonelDomainClusterSchema,
});

/**
 * `POST /api/colonel/domains` and `GET /api/colonel/domains/:extid` →
 * `{ record: <full safe_dump>, details: { cluster } }`.
 */
export const colonelDomainDetailResponseSchema = createApiResponseSchema(
  colonelDomainDetailRecordSchema,
  colonelDomainDetailsSchema
);

export type ColonelDomainDetailRecord = z.infer<typeof colonelDomainDetailRecordSchema>;
export type ColonelDomainCluster = z.infer<typeof colonelDomainClusterSchema>;
export type ColonelDomainDetailResponse = z.infer<typeof colonelDomainDetailResponseSchema>;
