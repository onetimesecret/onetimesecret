// src/schemas/api/domains/responses/domain-recipients.ts
//
// Response schemas for domain incoming secrets recipients API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/recipients
// - PUT /api/domains/:domain_extid/recipients
// - DELETE /api/domains/:domain_extid/recipients

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';

// ---------------------------------------------------------------------------
// Response-specific schemas
// ---------------------------------------------------------------------------

/**
 * Schema for a single recipient in response payloads.
 *
 * Response format uses digest (hash) instead of email to protect privacy.
 * The display_name is derived from the name provided at creation time.
 */
export const domainRecipientResponseSchema = z.object({
  /** Hashed identifier for the recipient (not the actual email). */
  digest: z.string().min(1),
  /** Display name for the recipient. */
  display_name: z.string(),
});

export type DomainRecipientResponse = z.infer<typeof domainRecipientResponseSchema>;

/**
 * Schema for the recipients record in API responses.
 *
 * Contains the array of configured recipients for a domain.
 */
export const domainRecipientsRecordSchema = z.object({
  /** Array of configured recipients. */
  recipients: z.array(domainRecipientResponseSchema),
});

export type DomainRecipientsRecord = z.infer<typeof domainRecipientsRecordSchema>;

// ---------------------------------------------------------------------------
// Response-specific details schema
// ---------------------------------------------------------------------------

/**
 * Domain recipients response details schema.
 *
 * Optional metadata that may accompany domain recipients responses.
 */
export const domainRecipientsDetailsSchema = z.object({
  /** Whether the current user can manage recipients for this domain. */
  can_manage: z.boolean().optional(),
  /** Maximum number of recipients allowed for this domain. */
  max_recipients: z.number().optional(),
});

export type DomainRecipientsDetails = z.infer<typeof domainRecipientsDetailsSchema>;

// ---------------------------------------------------------------------------
// Envelope-wrapped response schemas
// ---------------------------------------------------------------------------

/**
 * Response schema for GET /api/domains/:domain_extid/recipients
 *
 * Returns the list of configured recipients for the domain.
 */
export const getDomainRecipientsResponseSchema = createApiResponseSchema(
  domainRecipientsRecordSchema,
  domainRecipientsDetailsSchema
);

export type GetDomainRecipientsResponse = z.infer<typeof getDomainRecipientsResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/recipients
 *
 * Returns the replaced recipients list.
 */
export const putDomainRecipientsResponseSchema = createApiResponseSchema(
  domainRecipientsRecordSchema,
  domainRecipientsDetailsSchema
);

export type PutDomainRecipientsResponse = z.infer<typeof putDomainRecipientsResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/recipients
 *
 * Returns a success confirmation with optional details.
 */
export const deleteDomainRecipientsResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteDomainRecipientsResponse = z.infer<typeof deleteDomainRecipientsResponseSchema>;
