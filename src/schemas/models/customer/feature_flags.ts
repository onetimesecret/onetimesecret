import { transforms } from '@/utils/transforms';
import { z } from 'zod';

/**
 * @fileoverview Feature flags schema with standardized validation
 *
 * Key improvements:
 * 1. Explicit validation for known flags
 * 2. Consistent type conversion at API boundaries
 * 3. Support for dynamic fields
 * 4. Clear documentation of flag purposes
 */

/**
 * Known feature flag keys
 * Using const enum pattern for better type safety and documentation
 */
export const FeatureFlagKeys = {
  // UI/UX Flags
  HOMEPAGE_TOGGLE: 'homepage_toggle', // Control branded homepage visibility
  THEME: 'theme', // UI theme preference (light/dark)
  LANGUAGE: 'language', // UI language preference

  // Limit Flags
  MAX_SECRETS: 'max_secrets', // Maximum number of secrets allowed
  MAX_SIZE: 'max_size', // Maximum secret size in bytes
  MAX_TTL: 'max_ttl', // Maximum time-to-live in seconds

  // Feature Access Flags
  API_ACCESS: 'api_access', // API access enabled
  CUSTOM_DOMAINS: 'custom_domains', // Custom domain support
  PRIVATE_SECRETS: 'private_secrets', // Private secret support
} as const;

/**
 * Theme options for UI preference
 */
export const ThemeOptions = {
  LIGHT: 'light',
  DARK: 'dark',
  SYSTEM: 'system',
} as const;

/**
 * Known boolean flags schema
 * These flags are expected to be boolean values from the API
 */
const booleanFlagsSchema = z.object({
  [FeatureFlagKeys.HOMEPAGE_TOGGLE]: transforms.fromString.boolean.optional(),
  [FeatureFlagKeys.API_ACCESS]: transforms.fromString.boolean.optional(),
  [FeatureFlagKeys.CUSTOM_DOMAINS]: transforms.fromString.boolean.optional(),
  [FeatureFlagKeys.PRIVATE_SECRETS]: transforms.fromString.boolean.optional(),
});

/**
 * Known numeric flags schema
 * These flags represent limits and should be numbers
 */
const numericFlagsSchema = z.object({
  [FeatureFlagKeys.MAX_SECRETS]: transforms.fromString.number.optional(),
  [FeatureFlagKeys.MAX_SIZE]: transforms.fromString.number.optional(),
  [FeatureFlagKeys.MAX_TTL]: transforms.fromString.number.optional(),
});

/**
 * Known string flags schema
 * These flags represent preferences or identifiers
 */
const stringFlagsSchema = z.object({
  [FeatureFlagKeys.THEME]: z.enum([
    ThemeOptions.LIGHT,
    ThemeOptions.DARK,
    ThemeOptions.SYSTEM,
  ]).optional(),
  [FeatureFlagKeys.LANGUAGE]: z.string().optional(),
});

/**
 * Combined feature flags schema
 * Merges known flag schemas and allows additional dynamic fields
 */
export const featureFlagsSchema = booleanFlagsSchema
  .merge(numericFlagsSchema)
  .merge(stringFlagsSchema)
  .catchall(z.union([z.boolean(), z.number(), z.string()]));

/**
 * Type definition for feature flags
 * Includes both known and dynamic fields
 */
export type FeatureFlags = z.infer<typeof featureFlagsSchema>;

/**
 * Type guard to check if a flag exists
 * Uses type-safe approach to check flag existence
 */
export const isKnownFlag = (flag: string): flag is keyof typeof FeatureFlagKeys => {
  return Object.values(FeatureFlagKeys).includes(flag as typeof FeatureFlagKeys[keyof typeof FeatureFlagKeys]);
};
