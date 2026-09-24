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
  // zod v4's `.default()` substitutes this value verbatim when the key is
  // absent from the input — unlike `.parse()`, it does NOT run the value
  // back through uiInterfaceSchema, so nested defaults (e.g. show_version)
  // never cascade in (see $ZodDefault in zod/v4/core/schemas.js). TypeScript
  // therefore requires the literal to already match the schema's full
  // OUTPUT type, even though only `enabled` is set on purpose here — the
  // cast records that this is intentional, not a truncated UiInterface.
  // bootstrap-schema-contract.spec.ts's "provides sensible defaults for
  // empty input" pins this exact partial shape, so don't "complete" it via
  // uiInterfaceSchema.parse({...}) (that would add show_version and break
  // the assertion).
  ui: uiInterfaceSchema.default({ enabled: true } as z.output<typeof uiInterfaceSchema>),
  messages: z.array(messageSchema).default([]),
  // Same verbatim-substitution caveat as `ui` above: organizations/
  // secret_activity are deliberately not cascaded into this literal.
  features: featuresSchema.default({ markdown: false } as z.output<typeof featuresSchema>),
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
