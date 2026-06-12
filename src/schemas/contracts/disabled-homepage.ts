// src/schemas/contracts/disabled-homepage.ts
//
// Disabled-homepage view configuration — frontend rendering knobs for the
// DisabledHomepage view shown when the homepage secret form is gated by auth.
//
// Two layers live here:
//
//  1. The variant enum + frontend default. The variant itself is a
//     per-domain setting (lives on homepageConfigCanonical), with a
//     frontend constant fallback for the canonical site / unconfigured
//     domains. Keeping the enum here lets both the URL-override parser
//     and the per-domain field share a single source of truth.
//
//  2. Tri-state operator overrides for the optional affordances
//     (show_promo, show_what_is_this). Auto-detection rules live in
//     `useDisabledConfig` — these are the operator overrides on top.

import { z } from 'zod';

/**
 * Visual variant for the disabled-homepage view.
 *
 * - `closed`: the quiet two-tagline placeholder (default). No CTA — the
 *   understated "members only" landing page private instances had before
 *   the refresh.
 * - `minimal`: quiet refresh of the two-tagline shape — small mark, headline,
 *   subtitle, and a sign-in CTA (one-click SSO when a single provider is the
 *   only login method, otherwise a link to /signin). No trust strip or promo.
 * - `v1`: the full hero refresh — mark, eyebrow, headline, CTA, trust strip,
 *   optional promo. Same SSO-aware CTA as `minimal`.
 *
 * New variants must be registered in the dispatcher map in
 * `DisabledHomepage.vue` *and* added here.
 */
export const disabledHomepageVariantSchema = z.enum(['v1', 'minimal', 'closed']);
export type DisabledHomepageVariant = z.infer<typeof disabledHomepageVariantSchema>;

/**
 * Frontend fallback variant — used when neither the per-domain
 * `homepage_config.disabled_homepage_variant` nor the `?variant` URL
 * override resolves to a value. The dispatcher and the composable both
 * import this so the default stays in one place.
 *
 * Defaults to `closed`: the quiet, pre-refresh landing page. Operators who
 * want a sign-in CTA on the gated homepage opt into `minimal` / `v1`
 * per-domain (or deployment-wide by changing this constant).
 */
export const DEFAULT_DISABLED_HOMEPAGE_VARIANT: DisabledHomepageVariant = 'closed';

/**
 * Tri-state operator override: null = use auto-detection rules,
 * true = force-show, false = force-hide.
 */
const overrideSchema = z.boolean().nullable().default(null);

export const disabledHomepageConfigSchema = z.object({
  show_promo: overrideSchema,
  show_what_is_this: overrideSchema,
});

export type DisabledHomepageConfig = z.infer<typeof disabledHomepageConfigSchema>;
