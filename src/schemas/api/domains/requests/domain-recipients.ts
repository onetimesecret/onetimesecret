// src/schemas/api/domains/requests/domain-recipients.ts
//
// Request schemas for domain incoming secrets recipients API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/recipients
// - PUT /api/domains/:domain_extid/recipients (full replacement)
// - DELETE /api/domains/:domain_extid/recipients
//
// Response schemas are in ../responses/domain-recipients.ts

import { z } from 'zod';

// Re-export response schemas for convenience
export {
  getDomainRecipientsResponseSchema,
  putDomainRecipientsResponseSchema,
  deleteDomainRecipientsResponseSchema,
  domainRecipientResponseSchema,
  domainRecipientsDetailsSchema,
  type GetDomainRecipientsResponse,
  type PutDomainRecipientsResponse,
  type DeleteDomainRecipientsResponse,
  type DomainRecipientResponse,
  type DomainRecipientsDetails,
} from '../responses/domain-recipients';

// ---------------------------------------------------------------------------
// Shared recipient input schema
// ---------------------------------------------------------------------------

/**
 * Schema for a single recipient in request payloads.
 *
 * Request format uses email (plaintext) which the backend hashes for storage.
 */
export const domainRecipientInputSchema = z.object({
  /** Email address of the recipient. */
  email: z.string().email(),
  /** Optional display name for the recipient. */
  name: z.string().optional(),
});

export type DomainRecipientInput = z.infer<typeof domainRecipientInputSchema>;

// ---------------------------------------------------------------------------
// GET /api/domains/:domain_extid/recipients
// ---------------------------------------------------------------------------

/**
 * Request parameters for getting domain recipients.
 *
 * Path params: domain_extid (domain external ID)
 */
export const getDomainRecipientsRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type GetDomainRecipientsRequest = z.infer<typeof getDomainRecipientsRequestSchema>;

// ---------------------------------------------------------------------------
// PUT /api/domains/:domain_extid/recipients (full replacement)
// ---------------------------------------------------------------------------

/**
 * Request body for PUT (full replacement) of domain recipients.
 *
 * PUT semantics: the request body IS the new state.
 * - Required field: recipients array
 * - Each recipient requires an email, optional name
 *
 * The backend will hash email addresses before storage to protect
 * recipient privacy. Responses return digest (hash) instead of email.
 */
export const putDomainRecipientsRequestSchema = z.object({
  /** Array of recipients to set for this domain. */
  recipients: z.array(domainRecipientInputSchema),
});

export type PutDomainRecipientsRequest = z.infer<typeof putDomainRecipientsRequestSchema>;

// ---------------------------------------------------------------------------
// DELETE /api/domains/:domain_extid/recipients
// ---------------------------------------------------------------------------

/**
 * Request parameters for deleting all domain recipients.
 *
 * Path params: domain_extid (domain external ID)
 */
export const deleteDomainRecipientsRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type DeleteDomainRecipientsRequest = z.infer<typeof deleteDomainRecipientsRequestSchema>;
