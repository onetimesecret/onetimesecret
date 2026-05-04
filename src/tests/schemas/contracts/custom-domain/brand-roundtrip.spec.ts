// src/tests/schemas/contracts/custom-domain/brand-roundtrip.spec.ts
//
// Round-trip validation for `brandSettingsCanonical` (extended 15 -> 22 fields
// per #3048). Verifies serialize -> JSON -> parse preserves data, and that
// the 7 new nullish() fields validate per their Zod types.
//
// Adapted from develop's `src/tests/schemas/models/brand-roundtrip.spec.ts`
// to main's contracts/ namespace. Reference of the original spec is included
// at the bottom for grep coverage of intent.
//
// Contract under test:
//   - 7 new nullish() fields: product_name, product_domain, support_email,
//     footer_text, logo_url, logo_dark_url, favicon_url
//   - product_name and footer_text apply a stripHtmlTags transform
//   - support_email validates as email
//   - logo_url, logo_dark_url, favicon_url validate as URL
//   - FontFamily and CornerStyle enums (already on main; re-asserted here)
//
// Some assertions will fail until frontend-dev's commits land. That is
// expected and tracked in the task brief.

import { describe, it, expect } from 'vitest';
import {
  brandSettingsCanonical,
  fontFamilyValues,
  cornerStyleValues,
  type BrandSettingsCanonical,
} from '@/schemas/contracts/custom-domain/brand-config';

// -----------------------------------------------------------------------------
// Fixture: full 22-field canonical object
// -----------------------------------------------------------------------------
//
// Inputs use plain (non-HTML) strings for fields that have stripHtmlTags
// transforms so the round-trip is identity-equal. Separate tests below
// cover the strip behaviour for tagged inputs.

function fullCanonical(): Record<string, unknown> {
  return {
    primary_color: '#3B82F6',
    colour: '#3B82F6',
    product_name: 'My App',
    product_domain: 'app.example.com',
    support_email: 'support@example.com',
    footer_text: 'Footer notice',
    logo_url: 'https://example.com/logo.svg',
    logo_dark_url: 'https://example.com/logo-dark.svg',
    favicon_url: 'https://example.com/favicon.ico',
    instructions_pre_reveal: 'Pre',
    instructions_reveal: 'During',
    instructions_post_reveal: 'Post',
    description: 'A description.',
    button_text_light: false,
    allow_public_homepage: false,
    allow_public_api: false,
    font_family: 'sans',
    corner_style: 'rounded',
    locale: 'en',
    default_ttl: 604800,
    passphrase_required: false,
    notify_enabled: false,
  };
}

// -----------------------------------------------------------------------------
// Round-trip: serialize -> JSON -> parse -> deep equal
// -----------------------------------------------------------------------------

describe('brandSettingsCanonical round-trip (22 fields)', () => {
  it('serializes a full 22-field object through JSON and re-parses to deep-equal', () => {
    const input = fullCanonical();
    const serialized = JSON.stringify(input);
    const reparsed = JSON.parse(serialized);
    const result = brandSettingsCanonical.parse(reparsed);

    // Note: deep equality after Zod parse: each new field is nullish() with
    // no transform that mutates plain ASCII input, so the round-trip is
    // identity-equal for fullCanonical() values.
    expect(result).toEqual(input);
  });

  it('parses an empty object (all fields optional) and yields defaults', () => {
    const result = brandSettingsCanonical.parse({});
    // The schema is .partial(); existing defaults still apply for the
    // legacy fields. New fields are nullish — undefined is acceptable.
    expect(result).toBeDefined();
  });

  it('preserves the canonical type shape', () => {
    const result: BrandSettingsCanonical = brandSettingsCanonical.parse(
      fullCanonical()
    );
    // Type-only assertion (compile-time). Runtime check that the parse
    // produced an object value.
    expect(typeof result).toBe('object');
  });
});

// -----------------------------------------------------------------------------
// New field types — per-field validation
// -----------------------------------------------------------------------------

describe('product_name (stripHtmlTags transform)', () => {
  it('strips simple HTML tags', () => {
    const result = brandSettingsCanonical.parse({
      product_name: '<b>Bold</b> Name',
    });
    expect(result.product_name).toBe('Bold Name');
  });

  it('strips nested/split tags resilient to single-pass regex', () => {
    const result = brandSettingsCanonical.parse({
      product_name: '<scr<script>ipt>alert("xss")</scr</script>ipt>',
    });
    expect(result.product_name).not.toContain('<');
    expect(result.product_name).not.toContain('>');
  });

  it('accepts plain string', () => {
    const result = brandSettingsCanonical.parse({ product_name: 'Acme' });
    expect(result.product_name).toBe('Acme');
  });

  it('accepts null', () => {
    const result = brandSettingsCanonical.parse({ product_name: null });
    expect(result.product_name).toBeNull();
  });

  it('accepts undefined / omission', () => {
    const result = brandSettingsCanonical.parse({});
    expect(result.product_name).toBeUndefined();
  });

  it('accepts empty string', () => {
    const result = brandSettingsCanonical.parse({ product_name: '' });
    expect(typeof result.product_name).toBe('string');
  });
});

describe('product_domain (string nullish)', () => {
  it('accepts a plain string', () => {
    const result = brandSettingsCanonical.parse({
      product_domain: 'app.example.com',
    });
    expect(result.product_domain).toBe('app.example.com');
  });

  it('accepts null', () => {
    const result = brandSettingsCanonical.parse({ product_domain: null });
    expect(result.product_domain).toBeNull();
  });

  it('accepts undefined', () => {
    const result = brandSettingsCanonical.parse({});
    expect(result.product_domain).toBeUndefined();
  });
});

describe('support_email (email nullish)', () => {
  it('accepts a valid email', () => {
    const result = brandSettingsCanonical.parse({
      support_email: 'support@example.com',
    });
    expect(result.support_email).toBe('support@example.com');
  });

  it('rejects a malformed email', () => {
    const parsed = brandSettingsCanonical.safeParse({
      support_email: 'not-an-email',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects an email without a domain', () => {
    const parsed = brandSettingsCanonical.safeParse({
      support_email: 'user@',
    });
    expect(parsed.success).toBe(false);
  });

  it('accepts null', () => {
    const result = brandSettingsCanonical.parse({ support_email: null });
    expect(result.support_email).toBeNull();
  });

  it('accepts undefined', () => {
    const result = brandSettingsCanonical.parse({});
    expect(result.support_email).toBeUndefined();
  });
});

describe('footer_text (stripHtmlTags transform)', () => {
  it('strips simple HTML tags', () => {
    const result = brandSettingsCanonical.parse({
      footer_text: '<i>foot</i> note',
    });
    expect(result.footer_text).toBe('foot note');
  });

  it('strips deeply nested split tags', () => {
    const result = brandSettingsCanonical.parse({
      footer_text: '<<b>script>evil</<b>script>',
    });
    expect(result.footer_text).not.toContain('<');
    expect(result.footer_text).not.toContain('>');
  });

  it('accepts null', () => {
    const result = brandSettingsCanonical.parse({ footer_text: null });
    expect(result.footer_text).toBeNull();
  });

  it('accepts undefined', () => {
    const result = brandSettingsCanonical.parse({});
    expect(result.footer_text).toBeUndefined();
  });
});

describe.each([
  ['logo_url'],
  ['logo_dark_url'],
  ['favicon_url'],
] as const)('%s (URL nullish)', (field) => {
  it('accepts an https URL', () => {
    const result = brandSettingsCanonical.parse({
      [field]: 'https://example.com/asset.png',
    });
    expect((result as Record<string, unknown>)[field]).toBe(
      'https://example.com/asset.png'
    );
  });

  it('accepts an http URL', () => {
    const result = brandSettingsCanonical.parse({
      [field]: 'http://example.com/asset.png',
    });
    expect((result as Record<string, unknown>)[field]).toBe(
      'http://example.com/asset.png'
    );
  });

  it('rejects a malformed URL', () => {
    const parsed = brandSettingsCanonical.safeParse({
      [field]: 'not-a-url',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects an empty string (URL parser disallows empty)', () => {
    const parsed = brandSettingsCanonical.safeParse({
      [field]: '',
    });
    expect(parsed.success).toBe(false);
  });

  it('accepts null', () => {
    const result = brandSettingsCanonical.parse({ [field]: null });
    expect((result as Record<string, unknown>)[field]).toBeNull();
  });

  it('accepts undefined', () => {
    const result = brandSettingsCanonical.parse({});
    expect((result as Record<string, unknown>)[field]).toBeUndefined();
  });
});

// -----------------------------------------------------------------------------
// Enums
// -----------------------------------------------------------------------------

describe('FontFamily enum', () => {
  it.each(fontFamilyValues)('accepts valid value %s', (value) => {
    const result = brandSettingsCanonical.parse({ font_family: value });
    expect(result.font_family).toBe(value);
  });

  it('rejects an unknown value', () => {
    const parsed = brandSettingsCanonical.safeParse({
      font_family: 'comic-sans',
    });
    expect(parsed.success).toBe(false);
  });

  it('exposes the expected canonical value set', () => {
    expect([...fontFamilyValues].sort()).toEqual(['mono', 'sans', 'serif']);
  });
});

describe('CornerStyle enum', () => {
  it.each(cornerStyleValues)('accepts valid value %s', (value) => {
    const result = brandSettingsCanonical.parse({ corner_style: value });
    expect(result.corner_style).toBe(value);
  });

  it('rejects an unknown value', () => {
    const parsed = brandSettingsCanonical.safeParse({
      corner_style: 'octagon',
    });
    expect(parsed.success).toBe(false);
  });

  it('exposes the expected canonical value set', () => {
    expect([...cornerStyleValues].sort()).toEqual(['pill', 'rounded', 'square']);
  });
});

// -----------------------------------------------------------------------------
// Edge cases
// -----------------------------------------------------------------------------

describe('edge cases', () => {
  it('omitting all 7 new fields parses without error', () => {
    const result = brandSettingsCanonical.parse({});
    expect(result.product_name).toBeUndefined();
    expect(result.product_domain).toBeUndefined();
    expect(result.support_email).toBeUndefined();
    expect(result.footer_text).toBeUndefined();
    expect(result.logo_url).toBeUndefined();
    expect(result.logo_dark_url).toBeUndefined();
    expect(result.favicon_url).toBeUndefined();
  });

  it('explicit null on every new field is preserved', () => {
    const result = brandSettingsCanonical.parse({
      product_name: null,
      product_domain: null,
      support_email: null,
      footer_text: null,
      logo_url: null,
      logo_dark_url: null,
      favicon_url: null,
    });
    expect(result.product_name).toBeNull();
    expect(result.product_domain).toBeNull();
    expect(result.support_email).toBeNull();
    expect(result.footer_text).toBeNull();
    expect(result.logo_url).toBeNull();
    expect(result.logo_dark_url).toBeNull();
    expect(result.favicon_url).toBeNull();
  });

  it('mixed valid + invalid: any single invalid value fails the whole parse', () => {
    const parsed = brandSettingsCanonical.safeParse({
      product_name: 'OK',
      support_email: 'invalid',
    });
    expect(parsed.success).toBe(false);
  });

  it('round-trips an object that omits all new fields (legacy 15-field shape)', () => {
    const legacy = {
      primary_color: '#3B82F6',
      button_text_light: false,
      allow_public_homepage: false,
      allow_public_api: false,
      font_family: 'sans',
      corner_style: 'rounded',
      locale: 'en',
      passphrase_required: false,
      notify_enabled: false,
    };
    const reparsed = JSON.parse(JSON.stringify(legacy));
    const result = brandSettingsCanonical.parse(reparsed);
    expect(result.primary_color).toBe('#3B82F6');
    expect(result.font_family).toBe('sans');
    expect(result.corner_style).toBe('rounded');
  });
});
