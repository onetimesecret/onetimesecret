// src/schemas/api/domains/responses/sso-config.ts
//
// Response schemas for domain SSO configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/sso
// - PUT /api/domains/:domain_extid/sso
// - PATCH /api/domains/:domain_extid/sso
// - DELETE /api/domains/:domain_extid/sso
// - POST /api/domains/:domain_extid/sso/metadata

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import { customDomainSsoConfigSchema } from '@/schemas/shapes/domains/sso-config';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * SSO config response details schema.
 *
 * Optional metadata that may accompany SSO config responses.
 */
export const ssoConfigDetailsSchema = z.object({
  /** Whether the current user can manage this SSO config. */
  can_manage: z.boolean().optional(),
  /** Whether the SSO config has been tested/validated. */
  is_validated: z.boolean().optional(),
  /** Last successful SSO authentication timestamp. */
  last_auth_at: z.number().nullable().optional(),
});

export type SsoConfigDetails = z.infer<typeof ssoConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/sso
 *
 * Returns the full SSO config with masked credentials.
 */
export const getSsoConfigResponseSchema = createApiResponseSchema(
  customDomainSsoConfigSchema,
  ssoConfigDetailsSchema
);

export type GetSsoConfigResponse = z.infer<typeof getSsoConfigResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/sso
 *
 * Returns the replaced SSO config with masked credentials.
 */
export const putSsoConfigResponseSchema = createApiResponseSchema(
  customDomainSsoConfigSchema,
  ssoConfigDetailsSchema
);

export type PutSsoConfigResponse = z.infer<typeof putSsoConfigResponseSchema>;

/**
 * Response schema for PATCH /api/domains/:domain_extid/sso
 *
 * Returns the updated SSO config with masked credentials.
 */
export const patchSsoConfigResponseSchema = createApiResponseSchema(
  customDomainSsoConfigSchema,
  ssoConfigDetailsSchema
);

export type PatchSsoConfigResponse = z.infer<typeof patchSsoConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/sso
 *
 * Returns a success confirmation with optional details.
 */
export const deleteSsoConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteSsoConfigResponse = z.infer<typeof deleteSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/domains/:domain_extid/sso/metadata
// ─────────────────────────────────────────────────────────────────────────────

/**
 * error_code values of a failed metadata fetch (`success: false`). The
 * discovery-check vocabulary with invalid_issuer renamed invalid_metadata_url
 * and discovery_* renamed metadata_*, plus invalid_metadata (a body the
 * parser rejects) and aggregate_metadata (a document with several IdPs).
 * The wire value stays a string: a code added later renders the server's
 * message until it has a label.
 */
export const SSO_METADATA_FETCH_ERROR_CODES = [
  'invalid_metadata_url',
  'blocked_target',
  'timeout',
  'ssl_error',
  'connection_failed',
  'http_error',
  'metadata_not_found',
  'metadata_too_large',
  'invalid_metadata',
  'aggregate_metadata',
  'unexpected_error',
] as const;

export type SsoMetadataFetchErrorCode = (typeof SSO_METADATA_FETCH_ERROR_CODES)[number];

/**
 * Record-level problem codes of a parsed metadata document. Every one but
 * tenant_level_entra_metadata blocks the import; that one is advisory.
 * Severity comes from the response, never from this list.
 */
export const SSO_METADATA_PROBLEM_CODES = [
  'invalid_entity_id',
  'invalid_sso_url',
  'no_sso_url',
  'unsupported_sso_binding',
  'no_signing_certificates',
  'no_usable_signing_certificates',
  'tenant_level_entra_metadata',
] as const;

export type SsoMetadataProblemCode = (typeof SSO_METADATA_PROBLEM_CODES)[number];

/**
 * One record-level problem. A severity this client does not know reads as
 * `blocking`: an import is only offered when nothing says it should not be.
 */
export const idpMetadataProblemSchema = z.object({
  code: z.string(),
  severity: z.enum(['blocking', 'advisory']).catch('blocking'),
  message: z.string(),
});

export type IdpMetadataProblem = z.infer<typeof idpMetadataProblemSchema>;

/**
 * One signing certificate from the metadata (signing use only; encryption
 * keys are never offered). `pem` is the value an import puts in idp_cert.
 * The fingerprints are display values for matching the certificate by eye:
 * SHA-256 identifies it, the SHA-1 thumbprint is what the Entra portal
 * shows. Neither is ever a trust input. `problem` is the reason a save
 * would refuse the certificate (expired, not yet valid, not RSA), or null
 * when it can be imported.
 */
export const idpMetadataCertificateSchema = z.object({
  pem: z.string(),
  subject: z.string(),
  /** ISO 8601 UTC. */
  not_before: z.string(),
  /** ISO 8601 UTC. */
  not_after: z.string(),
  fingerprint_sha256: z.string(),
  thumbprint_sha1: z.string(),
  problem: z
    .string()
    .nullish()
    .transform((v) => v ?? null),
});

export type IdpMetadataCertificate = z.infer<typeof idpMetadataCertificateSchema>;

/**
 * The parsed metadata (`success: true`). Parsing succeeded; that does not
 * make it importable: `problems` may carry a blocking entry, and a
 * certificate still has to be chosen. idp_sso_service_url is the
 * HTTP-Redirect endpoint only, null when no_sso_url or
 * unsupported_sso_binding is reported. Keys the client does not read
 * (user_id) are tolerated.
 */
export const idpMetadataPreviewResponseSchema = z.object({
  success: z.literal(true),
  /** The URL as submitted, stripped. */
  metadata_url: z.string(),
  idp_entity_id: z
    .string()
    .nullish()
    .transform((v) => v ?? null),
  idp_sso_service_url: z
    .string()
    .nullish()
    .transform((v) => v ?? null),
  signing_certificates: z.array(idpMetadataCertificateSchema),
  /** Every NameIDFormat the IdP advertises, for display only. */
  name_id_formats: z
    .array(z.string())
    .nullish()
    .transform((v) => v ?? []),
  problems: z.array(idpMetadataProblemSchema),
});

export type IdpMetadataPreviewResponse = z.infer<typeof idpMetadataPreviewResponseSchema>;

/**
 * A fetch or parse that failed (`success: false`), the Test Connection
 * failure envelope. `message` and `details.description` are English;
 * `details.error_code` is the stable key.
 */
export const idpMetadataFetchFailureResponseSchema = z.object({
  success: z.literal(false),
  metadata_url: z.string().nullish(),
  message: z.string(),
  details: z
    .object({
      error_code: z.string().nullish(),
      description: z.string().nullish(),
      http_status: z.number().nullish(),
      max_bytes: z.number().nullish(),
    })
    .nullish(),
});

export type IdpMetadataFetchFailureResponse = z.infer<typeof idpMetadataFetchFailureResponseSchema>;

/**
 * Response schema for POST /api/domains/:domain_extid/sso/metadata. HTTP 200
 * for both shapes; guard failures (session, ownership, SAML off, blank URL,
 * rate limit) are 4xx errors and never reach this schema.
 */
export const fetchIdpMetadataResponseSchema = z.discriminatedUnion('success', [
  idpMetadataPreviewResponseSchema,
  idpMetadataFetchFailureResponseSchema,
]);

export type FetchIdpMetadataResponse = z.infer<typeof fetchIdpMetadataResponseSchema>;
