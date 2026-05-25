// src/schemas/contracts/disabled-homepage.ts
//
// Disabled-homepage view configuration — frontend rendering knobs for the
// DisabledHomepage view shown when the homepage secret form is gated by auth.
//
// All fields are optional with sensible auto-detection defaults so the
// contract is forward-compatible: a backend that doesn't emit this block
// still produces the default behaviour, and operators can flip individual
// knobs without a frontend release once the backend wires it up.
//
// Auto-detection rules live in `useDisabledConfig` — these are the
// operator overrides.

import { z } from 'zod';

/**
 * Visual variant for the disabled-homepage view.
 *
 * - `v1`: the full hero refresh — mark, eyebrow, headline, CTA, trust strip,
 *   optional promo (default)
 * - `minimal`: quiet refresh of the legacy two-tagline shape — small mark,
 *   headline, subtitle, ghost CTA. No trust strip or promo.
 * - `legacy`: the original two-tagline placeholder (rollback target)
 *
 * New variants must be registered in the dispatcher map in
 * `DisabledHomepage.vue` *and* added here.
 */
export const disabledHomepageVariantSchema = z.enum(['v1', 'minimal', 'legacy']);
export type DisabledHomepageVariant = z.infer<typeof disabledHomepageVariantSchema>;

/**
 * Tri-state operator override: null = use auto-detection rules,
 * true = force-show, false = force-hide.
 */
const overrideSchema = z.boolean().nullable().default(null);

export const disabledHomepageConfigSchema = z.object({
  variant: disabledHomepageVariantSchema.default('v1'),
  show_promo: overrideSchema,
  show_what_is_this: overrideSchema,
});

export type DisabledHomepageConfig = z.infer<typeof disabledHomepageConfigSchema>;
