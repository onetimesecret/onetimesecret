// src/tests/components/BaseUnknownSecret.spec.ts
//
// Guards the corner-derivation migration (#3646, C13) on the props-only
// BaseUnknownSecret. The expired/burned/unknown-link cards used to honor only
// the legacy 3-value corner_style (and hardcode 'rounded-lg'), silently
// no-op'ing on any domain that set the richer border_radius. The root now
// mirrors identityStore's cornerClass ladder:
//   border_radius set  → 'rounded-brand' (supersedes corner_style)
//   corner_style set   → cornerStyleClasses map (rounded-md/xl/none)
//   unbranded / unset  → 'rounded-lg' (canonical default; UnknownReceipt path)
// Critically, exactly ONE border-radius utility must land on the root — a
// residual 'rounded-lg' alongside 'rounded-brand' would fight it (Tailwind
// resolves by generated-CSS order, not source order).

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import BaseUnknownSecret from '@/shared/components/base/BaseUnknownSecret.vue';
import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys (house convention). BaseUnknownSecret has no direct i18n, but
// keep the mock for parity with sibling specs / any transitive load.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

const brand = (over: Partial<BrandSettings> = {}): BrandSettings =>
  ({ ...over }) as BrandSettings;

const mountCard = (props: { branded?: boolean; brandSettings?: BrandSettings }) =>
  mount(BaseUnknownSecret, {
    props,
    global: { stubs: { OIcon: true } },
  });

// All border-radius utilities in play — assert the root carries exactly one.
const RADIUS_UTILS = ['rounded-lg', 'rounded-brand', 'rounded-none', 'rounded-md', 'rounded-xl'];

const radiusClasses = (classes: string[]) => classes.filter((c) => RADIUS_UTILS.includes(c));

describe('BaseUnknownSecret corner derivation (#3646)', () => {
  it('non-branded (UnknownReceipt path) → rounded-lg only, never rounded-brand/none', () => {
    const classes = mountCard({ branded: false }).classes();
    expect(classes).toContain('rounded-lg');
    expect(classes).not.toContain('rounded-brand');
    expect(classes).not.toContain('rounded-none');
    expect(radiusClasses(classes)).toEqual(['rounded-lg']);
  });

  it('branded + border_radius (string preset) → rounded-brand, legacy classes absent', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({ border_radius: 'md', corner_style: 'square' }),
    }).classes();
    expect(classes).toContain('rounded-brand');
    // border_radius supersedes corner_style — its 'rounded-none' must not appear.
    expect(classes).not.toContain('rounded-none');
    expect(classes).not.toContain('rounded-lg');
    expect(radiusClasses(classes)).toEqual(['rounded-brand']);
  });

  it('branded + border_radius (numeric px) → rounded-brand', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({ border_radius: 22 }),
    }).classes();
    expect(classes).toContain('rounded-brand');
    expect(radiusClasses(classes)).toEqual(['rounded-brand']);
  });

  it('branded + corner_style square (no border_radius) → rounded-none', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({ corner_style: 'square' }),
    }).classes();
    expect(classes).toContain('rounded-none');
    expect(classes).not.toContain('rounded-brand');
    expect(classes).not.toContain('rounded-lg');
    expect(radiusClasses(classes)).toEqual(['rounded-none']);
  });

  it('branded + corner_style pill → rounded-xl', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({ corner_style: 'pill' }),
    }).classes();
    expect(classes).toContain('rounded-xl');
    expect(radiusClasses(classes)).toEqual(['rounded-xl']);
  });

  it('branded + corner_style rounded → rounded-md', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({ corner_style: 'rounded' }),
    }).classes();
    expect(classes).toContain('rounded-md');
    expect(radiusClasses(classes)).toEqual(['rounded-md']);
  });

  it('branded + nothing set → rounded-lg default', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({}),
    }).classes();
    expect(classes).toContain('rounded-lg');
    expect(radiusClasses(classes)).toEqual(['rounded-lg']);
  });

  it('empty-string border_radius does not trigger rounded-brand', () => {
    const classes = mountCard({
      branded: true,
      brandSettings: brand({ border_radius: '', corner_style: 'square' }),
    }).classes();
    // '' is treated as unset → falls through to corner_style.
    expect(classes).not.toContain('rounded-brand');
    expect(classes).toContain('rounded-none');
    expect(radiusClasses(classes)).toEqual(['rounded-none']);
  });
});
