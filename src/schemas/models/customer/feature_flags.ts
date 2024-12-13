// src/schemas/models/customer/feature-flags.ts
import { z } from 'zod';

/**
 * Schema for customer feature flags configuration
 *
 * @description Defines the structure for feature flags that control customer-specific functionality
 *
 * @example
 * ```typescript
 * const flags: FeatureFlags = {
 *   homepage_toggle: true,
 *   max_secrets: 100,     // Number of secrets allowed
 *   theme: 'dark',        // UI theme preference
 *   custom_field: 'value' // Dynamic fields supported
 * };
 * ```
 */
export const featureFlagsSchema = z
  .object({
    homepage_toggle: z.boolean().optional(),
  })
  .catchall(z.union([z.boolean(), z.number(), z.string()]));

/**
 * Type definition for customer feature flags
 *
 * @remarks
 * Supports dynamic fields through catchall definition
 *
 * Feature flags include:
 *
 * - homepage_toggle: Controls visibility of branded homepage toggle on domains
 * table. By default, we keep secret generation on custom domains disabled to
 * avoid potential abuse and/or confusion on behalf of our customers, their
 * (intentional) users, and other (otherwise unknown) parties. This flag
 * allows customers to knowingly opt-in to this feature. Valid usecases
 * like training employees, sharing with partners, etc. are encouraged.
 *
 */
export type FeatureFlags = z.infer<typeof featureFlagsSchema>;
