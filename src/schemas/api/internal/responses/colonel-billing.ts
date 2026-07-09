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
