// src/schemas/utils/feature_flags.ts
import { z } from 'zod';

/**
 * Simple, flexible feature flags schema
 * Allows any key-value pairs of boolean flags
 */
export const featureFlagsSchema = z.record(z.string(), z.boolean());

/**
 * Type definition for feature flags
 */
export type FeatureFlags = z.infer<typeof featureFlagsSchema>;

/**
 * Mixin to add feature flags support to any model schema
 * Handles transformation from API format to strongly-typed feature flags
 */
export const withFeatureFlags = <T extends z.ZodRawShape>(baseSchema: z.ZodObject<T>) =>
  baseSchema.extend({
    feature_flags: z
      .record(z.string(), z.union([z.boolean(), z.number(), z.string()]))
      .transform((val): FeatureFlags => {
        // Validate the shape matches FeatureFlags
        const featureFlags = val as FeatureFlags;
        return featureFlags;
      })
      .default({}),
  });

/**
 * Utility to check if a feature flag is enabled
 * @param flags The feature flags object
 * @param flagName The name of the flag to check
 * @returns Boolean indicating if the flag is true
 */
export const isFeatureEnabled = (flags: FeatureFlags, flagName: string): boolean =>
  flags[flagName] === true;
