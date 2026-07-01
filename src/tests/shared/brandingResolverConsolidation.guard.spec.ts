// src/tests/shared/brandingResolverConsolidation.guard.spec.ts
//
// Guardrail for the brand-identity resolver consolidation.
//
// The recurring "OTS branding leaked onto a neutral / custom-domain surface"
// class of bug (A1/A3/A4) came from surfaces re-deriving brand identity from
// raw bootstrap fields by hand instead of routing through the central resolver
// (identityStore). This test pins the consolidation so a future edit cannot
// silently re-introduce a hand-rolled product-name fallback or a hardcoded
// "Onetime Secret" literal in the migrated surfaces.
//
// It is deliberately source-level rather than behavioral: the behavioral
// guarantees live in identityStore.spec, MastHead(.customDomain).spec,
// DefaultLogo.spec and usePageTitle.spec. This file protects the *structure*
// that makes those guarantees hold in one place.

import { readFileSync } from 'fs';
import { resolve } from 'path';
import { describe, expect, it } from 'vitest';

const read = (relPath: string): string =>
  readFileSync(resolve(process.cwd(), relPath), 'utf-8');

/**
 * Strips comments so the "no re-derivation" assertions look only at executable
 * code, not at documentation that legitimately names the very things we forbid
 * in code (e.g. a comment explaining the A4 "Onetime Secret" leak).
 */
function stripComments(src: string): string {
  return src
    .replace(/<!--[\s\S]*?-->/g, '') // SFC HTML comments
    .replace(/\/\*[\s\S]*?\*\//g, '') // block comments
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1'); // line comments (preserve `://`)
}

const MASTHEAD = 'src/shared/components/layout/MastHead.vue';
const DEFAULT_LOGO = 'src/shared/components/logos/DefaultLogo.vue';
const USE_PAGE_TITLE = 'src/shared/composables/usePageTitle.ts';

describe('branding resolver consolidation guardrail', () => {
  describe('MastHead routes brand identity through identityStore', () => {
    const raw = read(MASTHEAD);
    const code = stripComments(raw);

    it('does not re-derive the product name from the raw bootstrap field', () => {
      expect(code).not.toContain('brand_product_name');
      expect(code).not.toContain('NEUTRAL_BRAND_DEFAULTS');
    });

    it('does not hardcode the OTS platform name', () => {
      expect(code).not.toContain('Onetime Secret');
    });

    it('consumes the resolver (useProductIdentity + productName + showPlatformIdentity)', () => {
      expect(raw).toContain('useProductIdentity');
      expect(raw).toContain('productName');
      expect(raw).toContain('showPlatformIdentity');
    });
  });

  describe('DefaultLogo resolves the product-name fallback through the shared helper', () => {
    // DefaultLogo is the app-wide fallback mark, so it stays lightweight and
    // uses resolveProductName directly rather than pulling in the identity
    // store. Reading the raw brand_product_name to feed the helper is fine —
    // what we forbid is re-implementing the fallback or hardcoding the literal.
    const raw = read(DEFAULT_LOGO);
    const code = stripComments(raw);

    it('does not re-derive the neutral fallback by hand', () => {
      expect(code).not.toContain('NEUTRAL_BRAND_DEFAULTS');
    });

    it('does not hardcode the OTS platform name', () => {
      expect(code).not.toContain('Onetime Secret');
    });

    it('resolves the product name through the shared resolveProductName helper', () => {
      expect(raw).toContain('resolveProductName');
    });
  });

  describe('usePageTitle uses the shared neutral fallback, never a hardcoded literal', () => {
    const raw = read(USE_PAGE_TITLE);
    const code = stripComments(raw);

    it('does not hardcode the OTS platform name', () => {
      expect(code).not.toContain('Onetime Secret');
      expect(code).not.toContain('APP_NAME');
    });

    it('resolves the product name through the shared resolveProductName helper', () => {
      expect(raw).toContain('resolveProductName');
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// stripComments self-test
//
// The guardrail above is deliberately source-text based, so its correctness
// hinges entirely on stripComments: it must remove documentation that names the
// forbidden tokens while preserving real code — crucially, a `//` inside a
// `://` URL is NOT a comment. These cases protect the regexes from a future
// edit that would silently make the guard pass (stripping real code) or fail
// (leaving a comment behind).
// ═══════════════════════════════════════════════════════════════════════════

describe('stripComments (guard helper)', () => {
  it('strips a line comment but keeps the code before it', () => {
    const out = stripComments("const x = 1; // brand_product_name in a comment");
    expect(out).toContain('const x = 1;');
    expect(out).not.toContain('brand_product_name');
  });

  it('strips a block comment', () => {
    const out = stripComments('const a = 1; /* NEUTRAL_BRAND_DEFAULTS */ const b = 2;');
    expect(out).not.toContain('NEUTRAL_BRAND_DEFAULTS');
    expect(out).toContain('const a = 1;');
    expect(out).toContain('const b = 2;');
  });

  it('strips an SFC/HTML comment', () => {
    const out = stripComments('<!-- Onetime Secret --><div id="logo" />');
    expect(out).not.toContain('Onetime Secret');
    expect(out).toContain('<div id="logo" />');
  });

  it('preserves a `://` URL literal (the // is not a comment)', () => {
    const out = stripComments("const u = 'https://cdn.example.com/logo.png';");
    expect(out).toContain('https://cdn.example.com/logo.png');
  });

  it('strips a trailing line comment without eating a preceding URL', () => {
    const out = stripComments("const u = 'https://cdn.example.com'; // domain_logo note");
    expect(out).toContain('https://cdn.example.com');
    expect(out).not.toContain('domain_logo');
  });
});
