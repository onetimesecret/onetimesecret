// src/schemas/api/internal/responses/colonel-domain-configs.ts

/**
 * Colonel (Admin) per-domain config management schemas.
 *
 * The colonel console can view, upsert, and delete the seven per-custom-domain
 * config records (signin/signup/homepage/api/incoming/sso/mailer), plus an
 * "ensure missing configs" action that materializes the five behavior-neutral
 * kinds with disabled defaults. Motivated by the v0.26.2 outage class: an
 * ABSENT config record fails closed (signin/signup/homepage/api/incoming OFF)
 * with no admin-visible way to see or fix it.
 *
 * These describe the shapes the four new colonel logic classes return:
 *   GET    /api/colonel/domains/:extid/configs         → colonelDomainConfigs
 *   PUT    /api/colonel/domains/:extid/configs/:kind   → colonelDomainConfigUpsert
 *   DELETE /api/colonel/domains/:extid/configs/:kind   → colonelDomainConfigDelete
 *   POST   /api/colonel/domains/:extid/configs/ensure  → colonelDomainConfigsEnsure
 *
 * The backend normalizes at the boundary: booleans are REAL JSON booleans
 * (never 'true'/'false' strings) and timestamps are integers or null. The
 * sso/mailer shapes are REDACTED — never a client_id/client_secret/api_key
 * value, only `has_*` presence flags.
 */

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

/** The seven per-domain config kinds, in the console's FIXED display order. */
export const DOMAIN_CONFIG_KINDS = [
  'signin',
  'signup',
  'homepage',
  'api',
  'incoming',
  'sso',
  'mailer',
] as const;

export type DomainConfigKind = (typeof DOMAIN_CONFIG_KINDS)[number];

/**
 * The five colonel-editable (and ensure-materializable) kinds. For these,
 * absent and present-but-disabled are behavior-equivalent, so upserting a
 * disabled record is behavior-neutral. sso/mailer are view/delete only: their
 * models require credentials on create and their ABSENT state means "fall back
 * to platform", so materializing empty records would be wrong.
 */
export const EDITABLE_DOMAIN_CONFIG_KINDS = [
  'signin',
  'signup',
  'homepage',
  'api',
  'incoming',
] as const;

export type EditableDomainConfigKind = (typeof EDITABLE_DOMAIN_CONFIG_KINDS)[number];

/**
 * The `record` envelope shared by all four responses — the resolved domain's
 * identity (matching the TransferDomain record shape).
 */
export const colonelDomainConfigsRecordSchema = z.object({
  domain_id: z.string(),
  extid: z.string(),
  display_domain: z.string(),
});

/** Unix-epoch integers (or null) — set on create, bumped on update. */
const configTimestamps = {
  created: z.number().nullable(),
  updated: z.number().nullable(),
};

/** signin: sign-in surface gates. All booleans are real booleans. */
export const colonelSigninConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  signin_enabled: z.boolean(),
  email_auth_enabled: z.boolean(),
  sso_enabled: z.boolean(),
  restrict_to: z.string().nullable(),
  ...configTimestamps,
});

/**
 * signup: sign-up surface gates + domain-allowlist validation strategy.
 * `validation_strategy` is nullable: a legacy/corrupt record can hydrate nil,
 * and this tool exists to REPAIR broken records — a strict string here would
 * fail gracefulParse and blank the whole configs panel. The server does NOT
 * coerce (the admin view shows honest raw state); the edit modal falls back
 * to 'passthrough' when prefilling.
 */
export const colonelSignupConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  signup_enabled: z.boolean(),
  autoverify: z.boolean(),
  validation_strategy: z.string().nullable(),
  allowed_signup_domains: z.array(z.string()),
  ...configTimestamps,
});

/**
 * homepage: homepage-secrets gate. The deprecated read-echo
 * `signup_enabled`/`signin_enabled` fields are deliberately EXCLUDED
 * (ADR-030: no display authority).
 */
export const colonelHomepageConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  secrets_mode: z.string(),
  disabled_homepage_variant: z.string().nullable(),
  ...configTimestamps,
});

/** api: public-API gate. */
export const colonelApiConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  ...configTimestamps,
});

/** incoming: incoming-secrets gate. `ready` mirrors the model's `ready?`. */
export const colonelIncomingConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  ready: z.boolean(),
  recipients: z.array(z.object({ email: z.string(), name: z.string().nullable().optional() })),
  ...configTimestamps,
});

/**
 * sso (REDACTED): tenant SSO provider. Credential VALUES never appear —
 * `has_client_id`/`has_client_secret` are presence flags only. Free-text
 * fields are nullable for parse resilience on this view-only kind.
 */
export const colonelSsoConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  provider_type: z.string().nullable(),
  display_name: z.string().nullable(),
  issuer: z.string().nullable(),
  tenant_id: z.string().nullable(),
  has_client_id: z.boolean(),
  has_client_secret: z.boolean(),
  allowed_domains: z.array(z.string()),
  enforce_sso_only: z.boolean(),
  grant_org_scope: z.boolean(),
  ...configTimestamps,
});

/**
 * mailer (REDACTED): per-domain mail sending. `api_key` and the jsonkey DNS
 * diagnostic blobs are never serialized. Free-text fields are nullable for
 * parse resilience on this view-only kind.
 */
export const colonelMailerConfigSchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  provider: z.string().nullable(),
  from_name: z.string().nullable(),
  from_address: z.string().nullable(),
  reply_to: z.string().nullable(),
  sending_mode: z.string().nullable(),
  verification_status: z.string().nullable(),
  dns_verified: z.boolean(),
  provider_verified: z.boolean(),
  has_api_key: z.boolean(),
  ...configTimestamps,
});

/** One GET entry: whether the record exists + its serialized form (or null). */
function configEntrySchema<TConfig extends z.ZodTypeAny>(configSchema: TConfig) {
  return z.object({ exists: z.boolean(), config: configSchema.nullable() });
}

/** All seven entries, keyed by kind slug. Every key is always present. */
export const colonelDomainConfigsMapSchema = z.object({
  signin: configEntrySchema(colonelSigninConfigSchema),
  signup: configEntrySchema(colonelSignupConfigSchema),
  homepage: configEntrySchema(colonelHomepageConfigSchema),
  api: configEntrySchema(colonelApiConfigSchema),
  incoming: configEntrySchema(colonelIncomingConfigSchema),
  sso: configEntrySchema(colonelSsoConfigSchema),
  mailer: configEntrySchema(colonelMailerConfigSchema),
});

export const colonelDomainConfigsDetailsSchema = z.object({
  configs: colonelDomainConfigsMapSchema,
});

/**
 * Any single serialized config, as returned by the upsert ack. Ordered
 * most-specific-first: `api`'s shape is a strict subset of the others, so it
 * must be tried LAST or a union match would silently strip sibling fields.
 */
export const colonelDomainConfigSchema = z.union([
  colonelSigninConfigSchema,
  colonelSignupConfigSchema,
  colonelHomepageConfigSchema,
  colonelIncomingConfigSchema,
  colonelApiConfigSchema,
]);

/**
 * Upsert ack: create-if-missing else partial update, echoing the new state.
 * `kind` is the EDITABLE enum — the server 422s a PUT on sso/mailer, so only
 * the five editable slugs can be echoed; anything else is a backend
 * regression the tripwire should catch.
 */
export const colonelDomainConfigUpsertDetailsSchema = z.object({
  kind: z.enum(EDITABLE_DOMAIN_CONFIG_KINDS),
  outcome: z.enum(['created', 'updated']),
  config: colonelDomainConfigSchema,
});

/** Delete ack. All seven kinds are deletable; a missing record 404s instead. */
export const colonelDomainConfigDeleteDetailsSchema = z.object({
  kind: z.enum(DOMAIN_CONFIG_KINDS),
  deleted: z.boolean(),
});

/**
 * Ensure ack. On a dry run, `created` = the kinds that WOULD be created.
 * sso/mailer always land in `skipped` (credentials required — materializing
 * empty records would be wrong). `created`/`existing` carry ONLY the
 * materializable slugs (the ensure operation iterates exactly those five,
 * which coincide with the editable kinds), so they use the EDITABLE enum as
 * a tripwire; `skipped` uses the full kind enum.
 */
export const colonelDomainConfigsEnsureDetailsSchema = z.object({
  dry_run: z.boolean(),
  created: z.array(z.enum(EDITABLE_DOMAIN_CONFIG_KINDS)),
  existing: z.array(z.enum(EDITABLE_DOMAIN_CONFIG_KINDS)),
  skipped: z.array(z.object({ kind: z.enum(DOMAIN_CONFIG_KINDS), reason: z.string() })),
});

// Wrapped response schemas — registered in `registry.ts` under the exact keys
// the backend logic classes declare in their `SCHEMAS` consts.

/** `GET /api/colonel/domains/:extid/configs` — key `colonelDomainConfigs`. */
export const colonelDomainConfigsResponseSchema = createApiResponseSchema(
  colonelDomainConfigsRecordSchema,
  colonelDomainConfigsDetailsSchema
);

/** `PUT /api/colonel/domains/:extid/configs/:kind` — key `colonelDomainConfigUpsert`. */
export const colonelDomainConfigUpsertResponseSchema = createApiResponseSchema(
  colonelDomainConfigsRecordSchema,
  colonelDomainConfigUpsertDetailsSchema
);

/** `DELETE /api/colonel/domains/:extid/configs/:kind` — key `colonelDomainConfigDelete`. */
export const colonelDomainConfigDeleteResponseSchema = createApiResponseSchema(
  colonelDomainConfigsRecordSchema,
  colonelDomainConfigDeleteDetailsSchema
);

/** `POST /api/colonel/domains/:extid/configs/ensure` — key `colonelDomainConfigsEnsure`. */
export const colonelDomainConfigsEnsureResponseSchema = createApiResponseSchema(
  colonelDomainConfigsRecordSchema,
  colonelDomainConfigsEnsureDetailsSchema
);

export type ColonelSigninConfig = z.infer<typeof colonelSigninConfigSchema>;
export type ColonelSignupConfig = z.infer<typeof colonelSignupConfigSchema>;
export type ColonelHomepageConfig = z.infer<typeof colonelHomepageConfigSchema>;
export type ColonelApiConfig = z.infer<typeof colonelApiConfigSchema>;
export type ColonelIncomingConfig = z.infer<typeof colonelIncomingConfigSchema>;
export type ColonelSsoConfig = z.infer<typeof colonelSsoConfigSchema>;
export type ColonelMailerConfig = z.infer<typeof colonelMailerConfigSchema>;
export type ColonelDomainConfig = z.infer<typeof colonelDomainConfigSchema>;
export type ColonelDomainConfigsMap = z.infer<typeof colonelDomainConfigsMapSchema>;
export type ColonelDomainConfigsDetails = z.infer<typeof colonelDomainConfigsDetailsSchema>;
export type ColonelDomainConfigUpsertDetails = z.infer<
  typeof colonelDomainConfigUpsertDetailsSchema
>;
export type ColonelDomainConfigDeleteDetails = z.infer<
  typeof colonelDomainConfigDeleteDetailsSchema
>;
export type ColonelDomainConfigsEnsureDetails = z.infer<
  typeof colonelDomainConfigsEnsureDetailsSchema
>;
export type ColonelDomainConfigsResponse = z.infer<typeof colonelDomainConfigsResponseSchema>;
