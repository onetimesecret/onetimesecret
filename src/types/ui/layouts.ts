// src/types/ui/layouts.ts

/**
 * Layout type definitions for Vue components
 *
 * WHY EXPLICIT INTERFACES (not z.infer)?
 * ─────────────────────────────────────────────────────────────────────────────
 * Vue's <script setup> macro uses compile-time type analysis for defineProps<T>().
 * The compiler-sfc performs STATIC analysis - it parses TypeScript AST without
 * executing any code. This means:
 *
 *   1. z.infer<typeof schema> cannot be resolved because it requires Zod's
 *      type-level computation at compile time
 *   2. Re-exports of z.infer types fail with "Unresolvable type reference"
 *   3. Only directly-defined interfaces/types in the imported module work
 *
 * Error you'll see if you try z.infer with defineProps:
 *   [@vue/compiler-sfc] Unresolvable type reference or unsupported built-in utility type
 *
 * PATTERN FOR ZOD + VUE:
 * ─────────────────────────────────────────────────────────────────────────────
 *   - src/schemas/ui/*.ts  → Zod schemas for runtime validation
 *   - src/types/ui/*.ts    → Explicit interfaces for Vue component props
 *
 * The schemas and interfaces must be kept in sync manually. When updating
 * schema fields, update the corresponding interface here.
 *
 * The schemas are still re-exported below for runtime validation use cases
 * (e.g., validating props from route meta or external API responses).
 */

/**
 * Logo configuration for masthead and other layout components.
 */
export interface LogoConfig {
  /** Logo URL (image path or component name ending with .vue) */
  url?: string;
  /** Logo alt text (falls back to i18n key) */
  alt?: string;
  /** Link destination for logo (defaults to '/') */
  href?: string;
  /** Logo size in pixels (defaults to 64) */
  size?: number;
  /** Whether to show company name next to logo */
  showSiteName?: boolean;
  /** Company name override (falls back to config or i18n) */
  siteName?: string;
  /** Tagline override (falls back to config or i18n) */
  tagLine?: string;
  /** Custom aria label override */
  ariaLabel?: string;
  /** Whether to identify that we are in the colonel area */
  isColonelArea?: boolean;
  /** Whether a user is present (logged in partially or fully) */
  isUserPresent: boolean;
}

/**
 * UI display configuration for layout components.
 */
export interface LayoutDisplay {
  displayGlobalBroadcast: boolean;
  displayMasthead: boolean;
  displayNavigation: boolean;
  displayPrimaryNav: boolean;
  displayFooterLinks: boolean;
  displayFeedback: boolean;
  displayVersion: boolean;
  displayPoweredBy: boolean;
  displayToggles: boolean;
}

/**
 * Single interface for all layout properties.
 * All LayoutDisplay properties are optional.
 */
export interface LayoutProps {
  displayGlobalBroadcast?: boolean;
  displayMasthead?: boolean;
  displayNavigation?: boolean;
  displayPrimaryNav?: boolean;
  displayFooterLinks?: boolean;
  displayFeedback?: boolean;
  displayVersion?: boolean;
  displayPoweredBy?: boolean;
  displayToggles?: boolean;
  /** Logo configuration for the layout */
  logo?: LogoConfig;
  /** Colonel mode enables admin features */
  colonel?: boolean;
}

/**
 * Extended layout properties for ImprovedLayout component.
 */
export interface ImprovedLayoutProps extends LayoutProps {
  /** Whether to show the sidebar */
  showSidebar?: boolean;
  /** Sidebar position */
  sidebarPosition?: 'left' | 'right';
}

// Re-export schemas for runtime validation use cases
export {
  improvedLayoutPropsSchema,
  layoutDisplaySchema,
  layoutPropsSchema,
  logoConfigSchema,
} from '@/schemas/ui/layouts';
