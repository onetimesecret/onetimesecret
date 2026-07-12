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

// Read-tolerance: unlike the canonical contract (which REJECTS an invalid
// border_radius to gate writes), the V3 READ shape must never let a stale
// cosmetic value fail the whole domain response. A retired/unknown value is
// coerced to `undefined` (unset) so the domain still loads. See the field
// comment in shapes/v3/custom-domain/brand.ts.
describe('V3 brandSettingsSchema border_radius read-tolerance', () => {
  it('passes valid presets and px through untouched', () => {
    expect(brandSettingsSchema.parse({ border_radius: 'md' }).border_radius).toBe('md');
    expect(brandSettingsSchema.parse({ border_radius: 22 }).border_radius).toBe(22);
    expect(brandSettingsSchema.parse({ border_radius: '22' }).border_radius).toBe('22');
  });

  it('coerces retired / unknown values to undefined instead of failing', () => {
    // 'custom' is the stale value observed in stored brand records; 'full' was
    // retired in WAVE2; 100 is out of the 0-64 range; '22.5' is non-integer.
    for (const stale of ['custom', 'full', 100, '22.5']) {
      const parsed = brandSettingsSchema.safeParse({ border_radius: stale });
      expect(parsed.success).toBe(true);
      expect(parsed.success && parsed.data.border_radius).toBeUndefined();
    }
  });

  it('preserves null and undefined', () => {
    expect(brandSettingsSchema.parse({ border_radius: null }).border_radius).toBeNull();
    expect(brandSettingsSchema.parse({}).border_radius).toBeUndefined();
  });
});
