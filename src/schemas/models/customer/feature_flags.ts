import { z } from 'zod';

/**
 * Simple, flexible feature flags schema
 * Allows any key-value pairs of boolean flags
 */
export const featureFlagsSchema = z.record(z.boolean());

/**
 * Type definition for feature flags
 */
export type FeatureFlags = z.infer<typeof featureFlagsSchema>;

/**
 * Utility to check if a feature flag is enabled
 * @param flags The feature flags object
 * @param flagName The name of the flag to check
 * @returns Boolean indicating if the flag is true
 */
export const isFeatureEnabled = (flags: FeatureFlags, flagName: string): boolean => {
  return flags[flagName] === true;
};
