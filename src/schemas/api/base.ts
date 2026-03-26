// src/schemas/api/base.ts
//
// Shared API response envelope schemas. These define the { record, details }
// structure used by all API versions. V2 logic classes originate the response
// contracts; V3 inherits them unchanged. The envelope helpers live here
// (version-neutral) rather than under a specific version directory.
//
// Previously: src/schemas/api/v3/base.ts

/**
 * API response envelope schemas and factory functions.
 *
 * These schemas define the standard `{ record, details }` structure used
 * by all API versions for consistent response handling. Factory functions
 * create typed response schemas for specific record types.
 *
 * @module api/base
 * @category API
 * @see {@link createApiResponseSchema} - Factory for single-record responses
 * @see {@link createApiListResponseSchema} - Factory for list responses
 */

import { z } from 'zod';

/**
 * Base schema patterns for API responses.
 *
 * Design Decisions:
 *
 * 1. Pure REST Semantics:
 *    - HTTP status codes indicate success (2xx) or error (4xx/5xx)
 *    - No redundant 'success' boolean field
 *    - Follows modern REST API best practices
 *
 * 2. Response Structure:
 *    Success responses (2xx):
 *    - record/records: primary payload
 *    - details: optional metadata
 *    - count: for list responses
 *    - user_id/shrimp: session/CSRF data
 *
 *    Error responses (4xx/5xx):
 *    - message: human-readable error message
 *    - code: machine-readable error code (e.g., "VALIDATION_ERROR")
 *    - details: optional structured error data
 *
 * 3. Single Record vs List Responses:
 *    We explicitly distinguish between:
 *    - Single record uses `record` field
 *    - List response uses `records` field
 *
 *    Benefits:
 *    - Explicit naming clearly indicates what to expect
 *    - Matches Ruby backend's response format
 *    - Type safety is more precise - compiler enforces correct expectations
 *    - Preferred over generic `data` field for API clarity
 *
 * 4. Type Parameters:
 *    Schemas use TypeScript generics to ensure:
 *    - Type safety for records
 *    - Flexible detail schemas
 *    - Proper type inference
 *
 * 5. Details Handling:
 *    - Optional details object
 *    - Defaults to record<string, unknown>
 *    - Can be extended with specific schemas
 *
 * 6. Naming Conventions:
 *    - user_id instead of custid (modern, clear naming)
 *    - Maps to Customer#objid internally but presents cleaner API
 *
 * @category API
 */
const apiResponseBaseSchema = z.object({
  user_id: z.string().optional(),
  shrimp: z.string().optional().default(''),
});

/**
 * Creates a typed API response schema for single-record endpoints.
 *
 * Wraps a record schema in the standard API envelope with optional details.
 * Use this for endpoints that return a single entity (GET /secrets/:id, POST /secrets).
 *
 * @typeParam TRecord - Zod schema type for the record payload
 * @typeParam TDetails - Zod schema type for optional details metadata
 *
 * @param recordSchema - Zod schema for the record field
 * @param detailsSchema - Optional Zod schema for the details field
 * @returns A Zod object schema with record, details, user_id, and shrimp fields
 *
 * @category API
 *
 * @example
 * ```typescript
 * import { secretSchema, secretDetailsSchema } from '@/schemas/shapes/v2/secret';
 *
 * // Create response schema for secret endpoint
 * const secretResponseSchema = createApiResponseSchema(
 *   secretSchema,
 *   secretDetailsSchema
 * );
 *
 * // Parse API response
 * const response = secretResponseSchema.parse(apiData);
 * console.log(response.record.shortid);  // Typed as string
 * console.log(response.details?.show_secret);  // Typed as boolean | undefined
 *
 * // Derive TypeScript type
 * type SecretResponse = z.infer<typeof secretResponseSchema>;
 * ```
 */
export const createApiResponseSchema = <
  TRecord extends z.ZodTypeAny,
  TDetails extends z.ZodTypeAny = z.ZodRecord<z.ZodString, z.ZodAny>,
>(
  recordSchema: TRecord,
  detailsSchema?: TDetails
) =>
  apiResponseBaseSchema.extend({
    record: recordSchema,
    details: (detailsSchema ?? z.record(z.string(), z.any())).optional() as z.ZodOptional<TDetails>,
  });

/**
 * Creates a typed API response schema for list endpoints.
 *
 * Wraps an array of records in the standard API envelope with optional details
 * and count. Use this for endpoints that return collections (GET /receipts).
 *
 * @typeParam TRecord - Zod schema type for each record in the array
 * @typeParam TDetails - Zod schema type for optional details metadata
 *
 * @param recordSchema - Zod schema for each item in the records array
 * @param detailsSchema - Optional Zod schema for the details field
 * @returns A Zod object schema with records array, details, count, user_id, and shrimp fields
 *
 * @category API
 *
 * @example
 * ```typescript
 * import { receiptBaseSchema, receiptDetailsSchema } from '@/schemas/shapes/v2/receipt';
 *
 * // Create response schema for receipt list endpoint
 * const receiptListResponseSchema = createApiListResponseSchema(
 *   receiptBaseSchema,
 *   receiptDetailsSchema
 * );
 *
 * // Parse API response
 * const response = receiptListResponseSchema.parse(apiData);
 * response.records.forEach(receipt => {
 *   console.log(receipt.shortid);  // Typed as string
 * });
 * console.log(`Total: ${response.count}`);  // Typed as number | undefined
 *
 * // Derive TypeScript type
 * type ReceiptListResponse = z.infer<typeof receiptListResponseSchema>;
 * ```
 */
export const createApiListResponseSchema = <
  TRecord extends z.ZodTypeAny,
  TDetails extends z.ZodTypeAny = z.ZodRecord<z.ZodString, z.ZodAny>,
>(
  recordSchema: TRecord,
  detailsSchema?: TDetails
) =>
  apiResponseBaseSchema.extend({
    records: z.array(recordSchema),
    details: (detailsSchema ?? z.record(z.string(), z.any())).optional() as z.ZodOptional<TDetails>,
    count: z.number().int().optional(),
  });

/**
 * Schema for API error responses (4xx/5xx status codes).
 *
 * @category API
 *
 * @example
 * ```typescript
 * // Parse error response
 * const error = apiErrorResponseSchema.parse({
 *   message: 'Secret not found',
 *   code: 'NOT_FOUND',
 * });
 *
 * // Display to user
 * showError(error.message);
 *
 * // Log for debugging
 * if (error.code) {
 *   logger.error(`API error: ${error.code}`, error.details);
 * }
 * ```
 */
export const apiErrorResponseSchema = z.object({
  /** Human-readable error message for display. */
  message: z.string(),
  /** Machine-readable error code (e.g., "VALIDATION_ERROR", "NOT_FOUND"). */
  code: z.string().optional(),
  /** Optional structured error data for debugging. */
  details: z.record(z.string(), z.unknown()).optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for base API response fields (user_id, shrimp). */
export type ApiBaseResponse = z.infer<typeof apiResponseBaseSchema>;

/** TypeScript type for API error responses. */
export type ApiErrorResponse = z.infer<typeof apiErrorResponseSchema>;

/** TypeScript type for single-record API responses. */
export type ApiRecordResponse<T> = z.infer<
  ReturnType<typeof createApiResponseSchema<z.ZodType<T>>>
>;

/** TypeScript type for list API responses. */
export type ApiRecordsResponse<T> = z.infer<
  ReturnType<typeof createApiListResponseSchema<z.ZodType<T>>>
>;
