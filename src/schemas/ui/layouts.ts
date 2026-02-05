// src/schemas/ui/layouts.ts

/**
 * Layout Zod schemas and derived types
 *
 * Schemas for UI layout configuration. While component props don't typically
 * need runtime validation, having schemas enables:
 * - Consistent pattern across the codebase
 * - Future runtime validation if props come from external sources
 * - Self-documenting type definitions
 */

import { z } from 'zod';

/**
 * LogoConfig schema
 *
 * Logo configuration for masthead and other layout components.
 */
export const logoConfigSchema = z.object({
  /** Logo URL (image path or component name ending with .vue) */
  url: z.string().optional(),
  /** Logo alt text (falls back to i18n key) */
  alt: z.string().optional(),
  /** Link destination for logo (defaults to '/') */
  href: z.string().optional(),
  /** Logo size in pixels (defaults to 64) */
  size: z.number().optional(),
  /** Whether to show company name next to logo */
  showSiteName: z.boolean().optional(),
  /** Company name override (falls back to config or i18n) */
  siteName: z.string().optional(),
  /** Tagline override (falls back to config or i18n) */
  tagLine: z.string().optional(),
  /** Custom aria label override */
  ariaLabel: z.string().optional(),
  /** Whether to identify that we are in the colonel area */
  isColonelArea: z.boolean().optional(),
  /** Whether a user is present (logged in partially or fully) */
  isUserPresent: z.boolean(),
});

export type LogoConfig = z.infer<typeof logoConfigSchema>;

/**
 * LayoutDisplay schema
 *
 * UI display configuration for layout components.
 */
export const layoutDisplaySchema = z.object({
  displayGlobalBroadcast: z.boolean(),
  displayMasthead: z.boolean(),
  displayNavigation: z.boolean(),
  displayPrimaryNav: z.boolean(),
  displayFooterLinks: z.boolean(),
  displayFeedback: z.boolean(),
  displayVersion: z.boolean(),
  displayPoweredBy: z.boolean(),
  displayToggles: z.boolean(),
});

export type LayoutDisplay = z.infer<typeof layoutDisplaySchema>;

/**
 * LayoutProps schema
 *
 * Single interface for all layout properties.
 */
export const layoutPropsSchema = layoutDisplaySchema.partial().extend({
  /** Logo configuration for the layout */
  logo: logoConfigSchema.optional(),
  /** Colonel mode enables admin features */
  colonel: z.boolean().optional(),
});

export type LayoutProps = z.infer<typeof layoutPropsSchema>;

/**
 * ImprovedLayoutProps schema
 *
 * Extended layout properties for ImprovedLayout component.
 */
export const improvedLayoutPropsSchema = layoutPropsSchema.extend({
  /** Whether to show the sidebar */
  showSidebar: z.boolean().optional(),
  /** Sidebar position */
  sidebarPosition: z.enum(['left', 'right']).optional(),
});

export type ImprovedLayoutProps = z.infer<typeof improvedLayoutPropsSchema>;
