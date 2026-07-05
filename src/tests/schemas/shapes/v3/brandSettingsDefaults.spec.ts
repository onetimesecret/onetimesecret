// src/tests/schemas/shapes/v3/brandSettingsDefaults.spec.ts
//
// Locks the V3 brandSettingsSchema defaults so they stay aligned with the
// canonical contract (src/schemas/contracts/custom-domain/brand-config.ts) and
// NEUTRAL_BRAND_DEFAULTS. In particular, button_text_light must default to
// `true`: a `false` default silently shadowed the identityStore fallback
// (`brand?.button_text_light ?? DEFAULT_BUTTON_TEXT_LIGHT`), so unbranded
// domains rendered dark button text instead of the intended light.

import { describe, expect, it } from 'vitest';
import { brandSettingsSchema } from '@/schemas/shapes/v3/custom-domain';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';

describe('V3 brandSettingsSchema defaults', () => {
  it('defaults button_text_light to true (matches the canonical contract)', () => {
    const parsed = brandSettingsSchema.parse({});
    expect(parsed.button_text_light).toBe(true);
    expect(parsed.button_text_light).toBe(NEUTRAL_BRAND_DEFAULTS.button_text_light);
  });

  it('preserves an explicit button_text_light value', () => {
    expect(brandSettingsSchema.parse({ button_text_light: false }).button_text_light).toBe(false);
    expect(brandSettingsSchema.parse({ button_text_light: true }).button_text_light).toBe(true);
  });
});
