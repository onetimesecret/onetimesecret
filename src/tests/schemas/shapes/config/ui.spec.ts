// src/tests/schemas/shapes/config/ui.spec.ts
//
// Coverage for the ui shape — top-level `ui`/`api` defaults plus the
// homepage / header / footer_links / workspace_links sub-trees. The
// capabilities / help / logo schemas are pass-throughs (no augmentation).

import { describe, it, expect } from 'vitest';
import { uiSchema } from '@/schemas/contracts/config/section/ui';
import {
  userInterfaceShape,
  uiShape,
  apiShape,
  userInterfaceLogoShape,
  userInterfaceHeaderShape,
  userInterfaceFooterLinksShape,
  userInterfaceHomepageShape,
  uiCapabilitiesShape,
  uiHelpShape,
} from '@/schemas/shapes/config/section/ui';

describe('uiShape — top-level defaults', () => {
  it('enabled defaults to true', () => {
    expect(uiShape.parse({}).enabled).toBe(true);
  });

  it('contract leaves enabled undefined', () => {
    expect(uiSchema.parse({}).enabled).toBeUndefined();
  });

  it('applies homepage defaults when nested object provided', () => {
    const result = uiShape.parse({ homepage: {} });
    expect(result.homepage?.matching_cidrs).toEqual([]);
    expect(result.homepage?.mode_header).toBe('O-Homepage-Mode');
  });

  it('applies header.enabled default', () => {
    expect(uiShape.parse({ header: {} }).header?.enabled).toBe(true);
  });

  it('applies footer_links.enabled default', () => {
    expect(uiShape.parse({ footer_links: {} }).footer_links?.enabled).toBe(false);
  });

  it('applies workspace_links.enabled default', () => {
    expect(uiShape.parse({ workspace_links: {} }).workspace_links?.enabled).toBe(false);
  });
});

describe('apiShape', () => {
  it('enabled defaults to true', () => {
    expect(apiShape.parse({}).enabled).toBe(true);
  });
});

describe('userInterfaceHomepageShape — defaults', () => {
  it('fills matching_cidrs and mode_header', () => {
    const result = userInterfaceHomepageShape.parse({});
    expect(result.matching_cidrs).toEqual([]);
    expect(result.mode_header).toBe('O-Homepage-Mode');
  });

  it('leaves mode and public_links untouched', () => {
    const result = userInterfaceHomepageShape.parse({});
    expect(result.mode).toBeUndefined();
    expect(result.public_links).toBeUndefined();
  });
});

describe('userInterfaceHeaderShape', () => {
  it('enabled defaults to true', () => {
    expect(userInterfaceHeaderShape.parse({}).enabled).toBe(true);
  });

  it('preserves logo layout knobs / navigation passthrough (#3612)', () => {
    // header.branding is gone — the header carries only presentation knobs
    // (href / show_name / prominent); brand identity lives in the brand: block.
    const result = userInterfaceHeaderShape.parse({
      logo: { href: '/dashboard', show_name: true, prominent: false },
      navigation: { enabled: false },
    });
    expect(result.logo?.href).toBe('/dashboard');
    expect(result.logo?.show_name).toBe(true);
    expect(result.logo?.prominent).toBe(false);
    expect(result.navigation?.enabled).toBe(false);
  });

  it('accepts null logo knobs (unset means "use the surface default")', () => {
    const result = userInterfaceHeaderShape.parse({
      logo: { href: null, show_name: null, prominent: null },
    });
    expect(result.logo?.href).toBeNull();
    expect(result.logo?.show_name).toBeNull();
    expect(result.logo?.prominent).toBeNull();
  });

  it('strips a legacy branding nesting from the payload (#3612)', () => {
    // A legacy operator payload with the retired header.branding shape must
    // not survive parsing — brand identity is not modeled on the header.
    const result = userInterfaceHeaderShape.parse({
      branding: {
        logo: { url: 'DefaultLogo.vue', alt: 'x', link_to: '/' },
        site_name: 'One-Time Secret',
      },
    });
    expect(result).not.toHaveProperty('branding');
    expect(JSON.stringify(result)).not.toContain('One-Time Secret');
  });
});

describe('userInterfaceFooterLinksShape', () => {
  it('enabled defaults to false', () => {
    expect(userInterfaceFooterLinksShape.parse({}).enabled).toBe(false);
  });
});

describe('UI pass-through shapes (no augmentation)', () => {
  it('logo / capabilities / help parse populated input verbatim', () => {
    expect(userInterfaceLogoShape.parse({ show_name: true }).show_name).toBe(true);
    expect(userInterfaceLogoShape.parse({ href: '/vault' }).href).toBe('/vault');
    expect(uiCapabilitiesShape.parse({ burn: true }).burn).toBe(true);
    expect(uiHelpShape.parse({ enabled: false }).enabled).toBe(false);
  });
});

describe('userInterfaceShape — combined ui + api', () => {
  it('applies defaults to both branches when nested objects are empty', () => {
    const result = userInterfaceShape.parse({ ui: {}, api: {} });
    expect(result.ui?.enabled).toBe(true);
    expect(result.api?.enabled).toBe(true);
  });
});
