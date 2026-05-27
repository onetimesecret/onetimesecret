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

  it('preserves branding/navigation passthrough', () => {
    const result = userInterfaceHeaderShape.parse({
      branding: { site_name: 'OTS' },
      navigation: { enabled: false },
    });
    expect(result.branding?.site_name).toBe('OTS');
    expect(result.navigation?.enabled).toBe(false);
  });
});

describe('userInterfaceFooterLinksShape', () => {
  it('enabled defaults to false', () => {
    expect(userInterfaceFooterLinksShape.parse({}).enabled).toBe(false);
  });
});

describe('UI pass-through shapes (no augmentation)', () => {
  it('logo / capabilities / help parse populated input verbatim', () => {
    expect(userInterfaceLogoShape.parse({ url: '/img/logo.svg' }).url).toBe('/img/logo.svg');
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
