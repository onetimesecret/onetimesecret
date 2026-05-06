// src/schemas/contracts/custom-domain/brand-config.ts
//
// Brand settings contract — cosmetic branding fields requiring custom_branding entitlement.
// Feature toggles (homepage, API access) are managed via their own config endpoints.
//
// Architecture: contract -> shape -> API
//
// Default Value Strategy:
// This schema intentionally avoids `.default()` for `primary_color`. The
// schema's job is validation, not defaulting. Default resolution is handled
// by identityStore's 3-step fallback chain:
//
//   1. domain_branding.primary_color         (per-domain, from Redis)
//   2. bootstrapStore.brand_primary_color    (per-installation, from config)
//   3. NEUTRAL_BRAND_DEFAULTS.primary_color  (hardcoded neutral fallback)
//
// If the schema eagerly fills a default via `.default()`, the nullish
// coalescing (`??`) in the fallback chain never reaches step 2, making
// the global brand config ineffective. This matters for:
//   - Multi-tenant: domains without a color fall through to the
//     installation default (step 2) or the hardcoded default (step 3)
//   - Single-tenant elite: the installation sets its brand color in
//     config (step 2), and the schema must not mask it

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Sanitization helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Strips HTML tags from a string for XSS prevention at the schema boundary.
 *
 * Defense-in-depth: primary sanitization happens server-side in Ruby (Sanitize
 * gem). This regex approach is adequate because these fields only receive API
 * response data that the backend already sanitized. If these fields ever
 * accept direct user input on the frontend (bypassing the API), replace this
 * with DOMPurify or the browser's native DOMParser.
 *
 * @param val - The string value to sanitize, or null/undefined.
 * @returns The sanitized string with HTML tags removed, or null/undefined.
 */
function stripHtmlTags(val: string | null | undefined): string | null | undefined {
  if (val == null) return val;
  // Loop until stable to handle nested tags like <scr<script>ipt>.
  let result = val;
  let prev: string;
  do {
    prev = result;
    result = result.replace(/<[^>]*>/g, '');
  } while (result !== prev);
  // Strip stray angle brackets left by split-tag attacks.
  return result.replace(/[<>]/g, '').trim();
}

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
    /**
     * Primary brand color (hex format, e.g., #3B82F6).
     *
     * No `.default()` by design — see file header for the fallback chain.
     */
    primary_color: z
      .string()
      .regex(/^#(?:[0-9A-F]{6}|[0-9A-F]{3})$/i, 'Invalid hex color')
      .transform((val) => {
        // Normalize 3-digit hex to 6-digit (e.g. #F00 -> #FF0000).
        if (val && /^#[0-9A-F]{3}$/i.test(val)) {
          const [, r, g, b] = val.split('');
          return `#${r}${r}${g}${g}${b}${b}`.toUpperCase();
        }
        return val;
      })
      .nullish(),

    /** Legacy color field (deprecated). */
    colour: z.string().optional(),

    // ─────────────────────────────────────────────────────────────────────
    // Identity / contact / collateral
    // ─────────────────────────────────────────────────────────────────────

    /** Product name shown in headers, footers and emails. Sanitized. */
    product_name: z.string().transform(stripHtmlTags).nullish(),

    /** Public-facing product domain (e.g., example.com). */
    product_domain: z.string().nullish(),

    /** Support email address. */
    support_email: z.string().email().nullish(),

    /** Footer text shown on public pages. Sanitized. */
    footer_text: z.string().transform(stripHtmlTags).nullish(),

    /** Logo URL (light mode / default). */
    logo_url: z.string().url().nullish(),

    /** Logo URL used in dark mode contexts. */
    logo_dark_url: z.string().url().nullish(),

    /** Favicon URL. */
    favicon_url: z.string().url().nullish(),

    // ─────────────────────────────────────────────────────────────────────
    // Existing fields (preserved)
    // ─────────────────────────────────────────────────────────────────────

    /** Instructions shown before secret reveal. */
    instructions_pre_reveal: z.string().nullish(),

    /** Instructions shown during secret reveal. */
    instructions_reveal: z.string().nullish(),

    /** Instructions shown after secret reveal. */
    instructions_post_reveal: z.string().nullish(),

    /** Brand description. */
    description: z.string().optional(),

    /** Whether button text should be light colored. */
    button_text_light: z.boolean().default(true),

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
