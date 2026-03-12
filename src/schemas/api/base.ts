// src/schemas/api/base.ts
//
// Shared API response envelope schemas. These define the { record, details }
// structure used by all API versions. V2 logic classes originate the response
// contracts; V3 inherits them unchanged. The envelope helpers live here
// (version-neutral) rather than under a specific version directory.
//
// Previously: src/schemas/api/v3/base.ts

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
 */
const apiResponseBaseSchema = z.object({
  user_id: z.string().optional(),
  shrimp: z.string().optional().default(''),
});

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

// Error response schema for 4xx/5xx responses
export const apiErrorResponseSchema = z.object({
  message: z.string(),
  code: z.string().optional(), // Machine-readable error code (e.g., "VALIDATION_ERROR")
  details: z.record(z.string(), z.unknown()).optional(),
});

// Type exports for API responses
export type ApiBaseResponse = z.infer<typeof apiResponseBaseSchema>;
export type ApiErrorResponse = z.infer<typeof apiErrorResponseSchema>;
export type ApiRecordResponse<T> = z.infer<
  ReturnType<typeof createApiResponseSchema<z.ZodType<T>>>
>;
export type ApiRecordsResponse<T> = z.infer<
  ReturnType<typeof createApiListResponseSchema<z.ZodType<T>>>
>;
