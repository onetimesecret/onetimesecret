// src/schemas/api/internal/responses/colonel-billing.ts
//
// Per-resource colonel/admin schemas for the Billing catalog drift view
// (ticket #45, Phase 3).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are
// UNTOUCHED (the Zod tripwire, epic non-goal). This surfaces the READ-ONLY
// billing catalog / plan-drift capability inspected via CLI today
// (`bin/ots billing plans` + the catalog ops); there was no old colonel screen.
// Distinct `billing` namespace so it never collides with any other colonel
// per-resource schema file.
//
// Shapes verified against the colonel logic class
// (apps/api/colonel/logic/colonel/get_billing_catalog.rb), a thin READ adapter
// over the incumbent Billing::Plan source (list_plans + list_plans_from_config).
// Nothing here mutates, so there is no ack/mutation schema.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

// ============================================================================
// PlanEntry — one normalized catalog plan (same shape on both the config and
// live sides so drift compares like-for-like).
// ============================================================================

/**
 * A single plan in the catalog. `limits` is a flattened map of quota keys
 * (e.g. "teams.max") to their string values ("0" / "unlimited"); the backend
 * stringifies both sides so a config "0" and a cached "0" compare equal.
 * `description` is nullable — a plan may carry none.
 */
export const colonelBillingPlanSchema = z.object({
  planid: z.string(),
  name: z.string().nullable(),
  tier: z.string().nullable(),
  tenancy: z.string().nullable(),
  region: z.string().nullable(),
  display_order: z.number(),
  show_on_plans_page: z.boolean(),
  description: z.string().nullable(),
  entitlements: z.array(z.string()),
  limits: z.record(z.string(), z.string()),
});

// ============================================================================
// Drift — the computed config-vs-live difference, keyed by planid.
// ============================================================================

/** One plan present on both sides whose comparable fields diverge. */
export const colonelBillingDriftChangeSchema = z.object({
  planid: z.string(),
  name: z.string().nullable(),
  /** Which fields drift: any of "entitlements" / "limits" / "tier" / "name". */
  fields: z.array(z.string()),
});

/**
 * Drift summary. `in_sync` is true only when all three lists are empty.
 * `only_in_config` / `only_in_live` are planid lists; `changed` carries the
 * per-plan field-level divergence.
 */
export const colonelBillingDriftSchema = z.object({
  in_sync: z.boolean(),
  only_in_config: z.array(z.string()),
  only_in_live: z.array(z.string()),
  changed: z.array(colonelBillingDriftChangeSchema),
});

// ============================================================================
// Catalog details — the whole read-out.
// ============================================================================

/**
 * Billing catalog details. `source` is "stripe" when the live cache is
 * populated (drift is meaningful) or "local_config" when it is empty (dev / no
 * Stripe — live_plans is [] and drift cannot be evaluated). `stripe_configured`
 * mirrors that: live_plans.length > 0.
 */
export const colonelBillingCatalogDetailsSchema = z.object({
  source: z.enum(['stripe', 'local_config']),
  stripe_configured: z.boolean(),
  config_plans: z.array(colonelBillingPlanSchema),
  live_plans: z.array(colonelBillingPlanSchema),
  drift: colonelBillingDriftSchema,
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelBillingPlan = z.infer<typeof colonelBillingPlanSchema>;
export type ColonelBillingDriftChange = z.infer<typeof colonelBillingDriftChangeSchema>;
export type ColonelBillingDrift = z.infer<typeof colonelBillingDriftSchema>;
export type ColonelBillingCatalogDetails = z.infer<typeof colonelBillingCatalogDetailsSchema>;

// Wrapped response schema for the colonel Billing catalog drift view
// (ticket #45). Internal-only; consumed by the Vue admin console, never
// exposed publicly.
//
// The view imports this DIRECTLY (CONTRACT 3) so it typechecks independently of
// the registry; the Integrate step adds the registry key from wiringInstructions.
// Distinct `billing` namespace — does NOT touch any frozen colonel contract.
//
// READ-ONLY: no mutation/ack schema (spec: read-only drift, sync stays CLI).

// GET /api/colonel/billing/catalog → GetBillingCatalog
// The record is empty ({}); everything lives under `details`.
export const colonelBillingCatalogResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelBillingCatalogDetailsSchema
);

export type ColonelBillingCatalogResponse = z.infer<typeof colonelBillingCatalogResponseSchema>;

// ============================================================================
// Stripe-customer roster — GET /billing/stripe-organizations
// ============================================================================
//
// Sibling endpoint to the catalog above, NOT an extension of it: the catalog is
// an unpaginated config-vs-live snapshot, this is a paginated, index-backed
// roster of the tenants that are actually billed. Different cadence, different
// failure mode, different pagination — so a separate schema.
//
// Backed by ColonelAPI::Logic::Colonel::ListStripeOrganizations
// (SCHEMAS = { response: 'colonelStripeOrganizations' }) over
// Onetime::Operations::Billing::StripeOrganizations.
//
// Every field except the two identity keys is `.nullish()` on purpose: a
// partial or evolving payload should degrade ONE row rather than blank the
// whole table through a gracefulParse failure.

/** One organization that carries a Stripe customer id. */
export const colonelStripeOrganizationSchema = z.object({
  /** The organization's PUBLIC id — routes to /colonel/organizations/:id. */
  extid: z.string(),
  /** The Stripe customer id (`cus_…`) — the index field this list is keyed by. */
  stripe_customer_id: z.string(),
  org_id: z.string().nullish(),
  display_name: z.string().nullish(),
  owner_email: z.string().nullish(),
  billing_email: z.string().nullish(),
  planid: z.string().nullish(),
  stripe_subscription_id: z.string().nullish(),
  /** NOTE: a STRING (or null) on the wire, not a unix number. */
  subscription_period_end: z.string().nullish(),
  subscription_status: z.string().nullish(),
  sync_status: z.string().nullish(),
});

/**
 * The canonical four-field pagination envelope plus the two bound signals this
 * index-backed read carries:
 *
 * - `capped`      the HSCAN hit its entry bound (5,000), so `total_count`
 *                 UNDERSTATES the real population. Never render "showing X of
 *                 Y" as exact.
 * - `stale_count` index entries on THIS page whose organization no longer
 *                 loads; they are dropped, so a page can be SHORT. Do not
 *                 derive counts from rendered row length.
 *
 * The server emits both at the details root; they are accepted here as well so
 * the store can normalize from one place.
 */
export const colonelStripeOrganizationsPaginationSchema = z.object({
  page: z.number(),
  per_page: z.number(),
  total_count: z.number(),
  total_pages: z.number(),
  capped: z.boolean().optional(),
  stale_count: z.number().optional(),
});

export const colonelStripeOrganizationsDetailsSchema = z.object({
  organizations: z.array(colonelStripeOrganizationSchema),
  pagination: colonelStripeOrganizationsPaginationSchema,
  /** Server echo of the applied filters. Optional — never read for state. */
  filters: z.object({ search: z.string().nullish() }).optional(),
  capped: z.boolean().optional(),
  stale_count: z.number().optional(),
  /** HLEN of the index, ignoring `search`. Informational only. */
  indexed_total: z.number().optional(),
});

/** The record is empty ({}); everything lives under `details`. */
export const colonelStripeOrganizationsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelStripeOrganizationsDetailsSchema
);

export type ColonelStripeOrganization = z.infer<typeof colonelStripeOrganizationSchema>;
export type StripeOrganizationsPageMeta = z.infer<
  typeof colonelStripeOrganizationsPaginationSchema
>;
export type ColonelStripeOrganizationsResponse = z.infer<
  typeof colonelStripeOrganizationsResponseSchema
>;
