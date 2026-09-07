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
  // Deliberately partial literal defaults: this test helper pins the exact
  // default objects the contract spec asserts. Zod v4's `.default()` demands the
  // full output type (and returns the value verbatim, without re-parsing), so the
  // partial literals are cast rather than re-derived — re-deriving via
  // `schema.parse({})` would inject other defaulted fields and change the value.
  ui: uiInterfaceSchema.default({ enabled: true } as unknown as z.infer<typeof uiInterfaceSchema>),
  messages: z.array(messageSchema).default([]),
  features: featuresSchema.default({ markdown: false } as unknown as z.infer<typeof featuresSchema>),
  // Ruby always emits development; organization is conditional
  development: developmentConfigSchema.default(developmentConfigSchema.parse({})),
  organization: organizationSchema.optional(),
  supported_locales: z.array(z.string()).default([]),
  default_locale: z.string().default('en'),
});

/** Default values produced by parsing empty object through bootstrapUiSchema. */
export const BOOTSTRAP_UI_DEFAULTS = bootstrapUiSchema.parse({});

/** Type inferred from the test schema. */
export type BootstrapUiPayload = z.infer<typeof bootstrapUiSchema>;
