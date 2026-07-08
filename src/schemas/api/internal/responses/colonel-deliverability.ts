// src/schemas/api/internal/responses/colonel-deliverability.ts
//
// Wrapped response schemas for the email Deliverability section (bounces /
// complaints / suppression list) on the colonel Email Tools screen.
// Internal-only; never exposed publicly.
//
// The section component imports these DIRECTLY (CONTRACT 3) so it typechecks
// independently of the registry; the registry keys link them to the logic
// classes for OpenAPI generation.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelDeliverabilitySummaryDetailsSchema,
  colonelEmailSuppressionsDetailsSchema,
  colonelEmailSuppressionRemoveRecordSchema,
  colonelEmailSuppressionRemoveDetailsSchema,
  colonelDeliverabilityEventsDetailsSchema,
  colonelDeliverabilityIngestRecordSchema,
  colonelDeliverabilityIngestDetailsSchema,
} from '@/schemas/api/account/responses/colonel-deliverability';
import { z } from 'zod';

// GET /api/colonel/email/deliverability → GetEmailDeliverability
export const colonelEmailDeliverabilityResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelDeliverabilitySummaryDetailsSchema
);

// GET /api/colonel/email/deliverability/suppressions → ListEmailSuppressions
export const colonelEmailSuppressionsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelEmailSuppressionsDetailsSchema
);

// DELETE /api/colonel/email/deliverability/suppressions/:address → RemoveEmailSuppression
export const colonelEmailSuppressionRemoveResponseSchema = createApiResponseSchema(
  colonelEmailSuppressionRemoveRecordSchema,
  colonelEmailSuppressionRemoveDetailsSchema
);

// GET /api/colonel/email/deliverability/events → ListEmailDeliverabilityEvents
export const colonelEmailDeliverabilityEventsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelDeliverabilityEventsDetailsSchema
);

// POST /api/colonel/email/deliverability/events → IngestEmailDeliverabilityEvents
export const colonelEmailDeliverabilityIngestResponseSchema = createApiResponseSchema(
  colonelDeliverabilityIngestRecordSchema,
  colonelDeliverabilityIngestDetailsSchema
);

export type ColonelEmailDeliverabilityResponse = z.infer<
  typeof colonelEmailDeliverabilityResponseSchema
>;
export type ColonelEmailSuppressionsResponse = z.infer<
  typeof colonelEmailSuppressionsResponseSchema
>;
export type ColonelEmailSuppressionRemoveResponse = z.infer<
  typeof colonelEmailSuppressionRemoveResponseSchema
>;
export type ColonelEmailDeliverabilityEventsResponse = z.infer<
  typeof colonelEmailDeliverabilityEventsResponseSchema
>;
export type ColonelEmailDeliverabilityIngestResponse = z.infer<
  typeof colonelEmailDeliverabilityIngestResponseSchema
>;
