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
 *
 * Implemented as a single left-to-right scan rather than regex search-and-
 * replace: it removes every comment region in one pass with no residue, and it
 * sidesteps CodeQL's incomplete-multi-character-sanitization heuristic, which
 * fires on `String.replace`-based comment strippers regardless of any surrounding
 * fixpoint loop. (This helper only ever reads our own trusted source files, so
 * there is no real injection surface either way — the scan just keeps the guard
 * correct and the finding clear.) A `//` immediately preceded by `:` is treated
 * as part of a `://` URL, not a line comment, so URL literals survive.
 */
function stripComments(src: string): string {
  let out = '';
  let i = 0;
  while (i < src.length) {
    if (src.startsWith('<!--', i)) {
      const end = src.indexOf('-->', i + 4);
      i = end === -1 ? src.length : end + 3;
    } else if (src.startsWith('/*', i)) {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
    } else if (src.startsWith('//', i) && src[i - 1] !== ':') {
      const nl = src.indexOf('\n', i);
      i = nl === -1 ? src.length : nl; // keep the newline itself
    } else {
      out += src[i];
      i += 1;
    }
  }
  return out;
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

    it('does not read the raw domain_logo bootstrap field (routes via the resolver)', () => {
      // The header must not reach into raw identity fields — the tenant logo
      // comes from identity.logoUri / identity.logoSource, not domain_logo.
      expect(code).not.toContain('domain_logo');
    });

    it('does not hardcode the OTS platform name', () => {
      expect(code).not.toContain('Onetime Secret');
    });

    it('consumes the resolver (identity signals, not raw bootstrap identity)', () => {
      expect(raw).toContain('useProductIdentity');
      expect(raw).toContain('productName');
      expect(raw).toContain('showPlatformIdentity');
      expect(raw).toContain('logoUri');
      expect(raw).toContain('logoSource');
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

  // Invariant guarded by the comment scanner: however comments nest, no
  // forbidden token and no dangling comment opener may survive.
  it('removes nested HTML comments, leaving no forbidden token or `<!--` opener', () => {
    const out = stripComments('<!--<!-- brand_product_name -->--> keep');
    expect(out).not.toContain('brand_product_name');
    expect(out).not.toContain('<!--');
    expect(out).toContain('keep');
  });

  it('removes nested block comments, leaving no forbidden token or `/*` opener', () => {
    const out = stripComments('a /* /* NEUTRAL_BRAND_DEFAULTS */ */ b');
    expect(out).not.toContain('NEUTRAL_BRAND_DEFAULTS');
    expect(out).not.toContain('/*');
    expect(out).toContain('a');
    expect(out).toContain('b');
  });
});
