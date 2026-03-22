// src/tests/contracts/bootstrap-test-schema.ts
//
// Test-only schema for validating UI-specific portions of bootstrap.
// This schema is NOT used in production - it exists solely for contract tests.

import { z } from 'zod';
import {
  uiInterfaceSchema,
  messageSchema,
  featuresSchema,
  developmentConfigSchema,
  organizationSchema,
} from '@/schemas/contracts/bootstrap';

/**
 * Partial schema for testing UI-specific portions of bootstrap.
 * Used by contract tests to verify sub-schema behavior.
 */
export const bootstrapUiSchema = z.object({
  ui: uiInterfaceSchema.default({ enabled: true }),
  messages: z.array(messageSchema).default([]),
  features: featuresSchema.default({ markdown: false }),
  development: developmentConfigSchema.optional(),
  organization: organizationSchema.optional(),
  supported_locales: z.array(z.string()).default([]),
  default_locale: z.string().default('en'),
});

/** Default values produced by parsing empty object through bootstrapUiSchema. */
export const BOOTSTRAP_UI_DEFAULTS = bootstrapUiSchema.parse({});

/** Type inferred from the test schema. */
export type BootstrapUiPayload = z.infer<typeof bootstrapUiSchema>;
