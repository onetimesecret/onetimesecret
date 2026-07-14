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

/**
 * Normalizes a hex color to 6-digit uppercase, expanding 3-digit shorthand
 * (`#F00` → `#FF0000`). Assumes the value already passed the hex regex, so it
 * only handles the 3-vs-6 digit expansion. Mirrors `BrandSettings.normalize_color`.
 */
function normalizeHex(val: string | null | undefined): string | null | undefined {
  if (val == null) return val;
  if (/^#[0-9A-F]{3}$/i.test(val)) {
    const [, r, g, b] = val.split('');
    return `#${r}${r}${g}${g}${b}${b}`.toUpperCase();
  }
  return val.toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand settings canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Font family values for brand settings.
 *
 * Curated allowlist of self-hosted (`slab` = Zilla Slab) and system font
 * stacks. Kept in lockstep with the Ruby allowlist
 * (BrandSettingsConstants::FONTS) and the CSS stacks in
 * `src/shared/utils/brand-helpers.ts` (`fontFamilyStacks`). No free-form
 * fonts — this stays a closed allowlist so the XSS boundary holds.
 *
 * @category Contracts
 */
export const fontFamilyValues = [
  'sans',
  'serif',
  'mono',
  'system',
  'slab',
  'rounded',
  'humanist',
  'geometric',
] as const;
export type FontFamily = (typeof fontFamilyValues)[number];

/**
 * Corner style values for brand settings.
 *
 * Legacy 3-value vocabulary. Retained for back-compat; `border_radius` (below)
 * is the richer replacement and takes precedence when both are set.
 *
 * @category Contracts
 */
export const cornerStyleValues = ['rounded', 'pill', 'square'] as const;
export type CornerStyle = (typeof cornerStyleValues)[number];

/**
 * Named border-radius presets. `border_radius` accepts one of these keywords or
 * a whole number of pixels (0–64), both of which map to the `--radius-brand`
 * CSS variable at runtime. Mirrors BrandSettingsConstants::RADII (Ruby).
 *
 * @category Contracts
 */
export const borderRadiusPresets = ['none', 'sm', 'md', 'lg', 'xl'] as const;
export type BorderRadiusPreset = (typeof borderRadiusPresets)[number];

/** Maximum pixel value accepted for a numeric `border_radius`. */
export const BORDER_RADIUS_MAX_PX = 64;

/**
 * Validates a `border_radius` value: a named preset or an integer 0–64 (px),
 * accepting numeric strings so HTTP params (always strings) validate the same
 * as programmatic input. Mirrors `BrandSettings.valid_border_radius?` (Ruby).
 */
export function isValidBorderRadius(val: unknown): boolean {
  if (val == null) return false;
  const str = String(val).trim().toLowerCase();
  if ((borderRadiusPresets as readonly string[]).includes(str)) return true;
  if (!/^\d+$/.test(str)) return false;
  const px = Number(str);
  return px >= 0 && px <= BORDER_RADIUS_MAX_PX;
}

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

    /**
     * Secondary/accent brand color (hex). Drives the `--color-brand2-*` scale
     * at runtime. Normalized to 6-digit uppercase like primary_color.
     */
    secondary_color: z
      .string()
      .regex(/^#(?:[0-9A-F]{6}|[0-9A-F]{3})$/i, 'Invalid hex color')
      .transform(normalizeHex)
      .nullish(),

    /**
     * Surface/background color (hex). Drives `--color-brandbg` at runtime.
     */
    background_color: z
      .string()
      .regex(/^#(?:[0-9A-F]{6}|[0-9A-F]{3})$/i, 'Invalid hex color')
      .transform(normalizeHex)
      .nullish(),

    /**
     * Body text color (hex). Drives `--color-brandtext` at runtime. Format-only
     * validation (hex); WCAG contrast against background_color is surfaced as an
     * advisory warning in the editor UI, not enforced server-side (product
     * decision 2026-07).
     */
    text_color: z
      .string()
      .regex(/^#(?:[0-9A-F]{6}|[0-9A-F]{3})$/i, 'Invalid hex color')
      .transform(normalizeHex)
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
    description: z.string().nullish(),

    /** Whether button text should be light colored. */
    button_text_light: z.boolean().default(true),

    /** Font family for the interface (body text). */
    font_family: z.enum(fontFamilyValues).default('sans'),

    /**
     * Optional separate font for headings. Falls back to `font_family` when
     * unset. Same curated allowlist as `font_family`.
     */
    heading_font: z.enum(fontFamilyValues).nullish(),

    /** Corner style for UI elements (legacy; see `border_radius`). */
    corner_style: z.enum(cornerStyleValues).default('rounded'),

    /**
     * Border radius: a named preset (`none|sm|md|lg|xl`) or a whole number
     * of pixels 0–64 (accepted as string or number). Supersedes `corner_style`
     * when set. Stored as-is; mapped to `--radius-brand` on the frontend.
     */
    border_radius: z
      .union([z.string(), z.number()])
      .refine(isValidBorderRadius, {
        message: 'Invalid border radius - must be a preset or 0-64 px',
      })
      .nullish(),

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

/**
 * Domain-record icon projection (#3780).
 *
 * A deliberately narrow view of the icon hashkey that rides on the custom
 * domain record (backend `safe_dump`). It carries provenance + light metadata
 * but NEVER the base64 `encoded` bytes — those are large and served separately
 * via the image endpoint ({@link imagePropsCanonical}). Every field is a string
 * because the backend reads them straight off the Redis hashkey with no numeric
 * coercion, which is exactly why the numeric dimensions (width/height/bytes/
 * ratio) from `imagePropsCanonical` are intentionally omitted here — declaring
 * them as `z.number()` would reject the stringified values the wire carries.
 *
 * `favicon_source` gates the workspace "Refresh favicon" button: a
 * 'user_upload' icon can never be clobbered by a forced fetch
 * (FetchDomainFavicon#overwrite_guard), so the control is disabled for it.
 * Absent/null (older payloads, no icon) leaves the button enabled and the
 * backend overwrite-guard remains the real protection.
 *
 * @category Contracts
 */
export const domainIconMetaCanonical = z
  .object({
    /** Stored filename (e.g. favicon.ico). */
    filename: z.string().nullish(),

    /** MIME content type (e.g. image/png). */
    content_type: z.string().nullish(),

    /** Provenance: 'user_upload' | 'auto_fetch' | null (legacy untagged). */
    favicon_source: z.string().nullish(),
  })
  .partial();

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for brand settings. */
export type BrandSettingsCanonical = z.infer<typeof brandSettingsCanonical>;

/** TypeScript type for image properties. */
export type ImagePropsCanonical = z.infer<typeof imagePropsCanonical>;

/** TypeScript type for the domain-record icon projection. */
export type DomainIconMetaCanonical = z.infer<typeof domainIconMetaCanonical>;
