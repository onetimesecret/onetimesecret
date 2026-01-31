// src/types/ui/layouts.ts

/**
 * Layout types
 *
 * Re-exports from schemas. Schemas are defined in schemas/ui/layouts.ts
 * as the single source of truth. Types are derived via z.infer<>.
 */

export {
  improvedLayoutPropsSchema,
  layoutDisplaySchema,
  layoutPropsSchema,
  logoConfigSchema,
  type ImprovedLayoutProps,
  type LayoutDisplay,
  type LayoutProps,
  type LogoConfig,
} from '@/schemas/ui/layouts';
