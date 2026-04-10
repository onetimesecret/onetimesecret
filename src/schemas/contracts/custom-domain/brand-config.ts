// src/schemas/contracts/custom-domain/brand-config.ts
//
// Brand settings contract — cosmetic branding fields requiring custom_branding entitlement.
// Feature toggles (homepage, API access) are managed via their own config endpoints.
//
// Architecture: contract -> shape -> API

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Brand settings canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Font family values for brand settings.
 *
 * @category Contracts
 */
export const fontFamilyValues = ['sans', 'serif', 'mono'] as const;
export type FontFamily = (typeof fontFamilyValues)[number];

/**
 * Corner style values for brand settings.
 *
 * @category Contracts
 */
export const cornerStyleValues = ['rounded', 'pill', 'square'] as const;
export type CornerStyle = (typeof cornerStyleValues)[number];

/**
 * Canonical brand settings contract.
 *
 * Brand settings control the visual appearance of the custom domain's
 * secret sharing interface. Requires the custom_branding entitlement.
 *
 * Feature toggles like homepage and API access are managed separately
 * via their own config endpoints and contracts.
 *
 * @category Contracts
 */
export const brandSettingsCanonical = z
  .object({
    /** Primary brand color (hex format, e.g., #dc4a22). */
    primary_color: z
      .string()
      .regex(/^#[0-9A-Fa-f]{6}$/i)
      .default('#dc4a22'),

    /** Legacy color field (deprecated). */
    colour: z.string().optional(),

    /** Instructions shown before secret reveal. */
    instructions_pre_reveal: z.string().nullish(),

    /** Instructions shown during secret reveal. */
    instructions_reveal: z.string().nullish(),

    /** Instructions shown after secret reveal. */
    instructions_post_reveal: z.string().nullish(),

    /** Brand description. */
    description: z.string().optional(),

    /** Whether button text should be light colored. */
    button_text_light: z.boolean().default(false),

    /**
     * Whether public homepage is allowed.
     * @deprecated Managed via HomepageConfig endpoint. Retained in brand
     * response for backwards compatibility during migration.
     */
    allow_public_homepage: z.boolean().default(false),

    /**
     * Whether public API access is allowed.
     * @deprecated Will be managed via a dedicated config endpoint.
     * Retained in brand response for backwards compatibility.
     */
    allow_public_api: z.boolean().default(false),

    /** Font family for the interface. */
    font_family: z.enum(fontFamilyValues).default('sans'),

    /** Corner style for UI elements. */
    corner_style: z.enum(cornerStyleValues).default('rounded'),

    /** Locale/language code. */
    locale: z.string().default('en'),

    /** Default TTL for secrets (seconds). */
    default_ttl: z.number().nullish(),

    /** Whether passphrase is required by default. */
    passphrase_required: z.boolean().default(false),

    /** Whether email notifications are enabled by default. */
    notify_enabled: z.boolean().default(false),
  })
  .partial();

/**
 * Canonical image properties contract.
 *
 * Used for logo and icon image metadata.
 *
 * @category Contracts
 */
export const imagePropsCanonical = z
  .object({
    /** Base64 encoded image data. */
    encoded: z.string().optional(),

    /** MIME content type (e.g., image/png). */
    content_type: z.string().optional(),

    /** Original filename. */
    filename: z.string().optional(),

    /** File size in bytes. */
    bytes: z.number().optional(),

    /** Image width in pixels. */
    width: z.number().optional(),

    /** Image height in pixels. */
    height: z.number().optional(),

    /** Width/height aspect ratio. */
    ratio: z.number().optional(),
  })
  .partial();

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for brand settings. */
export type BrandSettingsCanonical = z.infer<typeof brandSettingsCanonical>;

/** TypeScript type for image properties. */
export type ImagePropsCanonical = z.infer<typeof imagePropsCanonical>;
