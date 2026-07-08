// src/tests/utils/parse/domain.spec.ts

import { analyzeDomain } from '@/utils/parse/domain';
import { describe, expect, it } from 'vitest';

/**
 * pnpm exec vitest run src/tests/utils/parse/domain.spec.ts
 *
 */

describe('analyzeDomain', () => {
  describe('empty input', () => {
    it('treats empty string as empty', () => {
      const result = analyzeDomain('');
      expect(result.empty).toBe(true);
      expect(result.valid).toBe(false);
      expect(result.apex).toBe(false);
      expect(result.registrable).toBe('');
      expect(result.subdomain).toBe('');
      expect(result.full).toBe('');
      expect(result.reason).toBeNull();
      expect(result.tld).toBe('');
    });

    it('treats whitespace-only string as empty', () => {
      const result = analyzeDomain('   ');
      expect(result.empty).toBe(true);
      expect(result.valid).toBe(false);
    });
  });

  describe('subdomains', () => {
    it('parses a single-label subdomain', () => {
      const result = analyzeDomain('secrets.acme.com');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(false);
      expect(result.registrable).toBe('acme.com');
      expect(result.subdomain).toBe('secrets');
      expect(result.tld).toBe('com');
    });

    it('parses a subdomain on a multi-part suffix', () => {
      const result = analyzeDomain('secrets.acme.co.uk');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(false);
      expect(result.registrable).toBe('acme.co.uk');
      expect(result.subdomain).toBe('secrets');
      expect(result.tld).toBe('co.uk');
    });

    it('parses a deeply nested subdomain', () => {
      const result = analyzeDomain('a.b.secrets.acme.com');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(false);
      expect(result.subdomain).toBe('a.b.secrets');
      expect(result.registrable).toBe('acme.com');
    });
  });

  describe('apex domains', () => {
    it('treats the registrable domain itself as apex', () => {
      const result = analyzeDomain('acme.com');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(true);
      expect(result.registrable).toBe('acme.com');
      expect(result.subdomain).toBe('');
      expect(result.tld).toBe('com');
    });

    it('treats www.<registrable> as apex', () => {
      const result = analyzeDomain('www.acme.com');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(true);
      expect(result.registrable).toBe('acme.com');
      expect(result.subdomain).toBe('');
      // `full` preserves what was typed even though it is treated as apex — the
      // form uses `registrable` (or the chosen subdomain) to build the host.
      expect(result.full).toBe('www.acme.com');
    });

    it('treats a multi-part-suffix registrable as apex', () => {
      const result = analyzeDomain('acme.co.uk');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(true);
      expect(result.registrable).toBe('acme.co.uk');
      expect(result.tld).toBe('co.uk');
    });
  });

  describe('invalid suffixes', () => {
    it('rejects a single-character TLD', () => {
      const result = analyzeDomain('example.c');
      expect(result.valid).toBe(false);
      expect(result.reason).toBe('suffix');
      expect(result.tld).toBe('c');
    });

    it('rejects a bare TLD', () => {
      // A single label has no dot, so it fails the okChars shape check first
      // and is classified 'malformed' before the suffix logic is reached.
      const result = analyzeDomain('com');
      expect(result.valid).toBe(false);
      expect(result.reason).toBe('malformed');
    });

    it('rejects a bare multi-part suffix', () => {
      const result = analyzeDomain('co.uk');
      expect(result.valid).toBe(false);
      expect(result.reason).toBe('suffix');
    });

    it('rejects a made-up TLD that is not in the public suffix list', () => {
      // Regression: ".afb" is not a real TLD, and the server rejects it too
      // (PublicSuffix default_rule: nil), so the form must not show apex cards.
      const result = analyzeDomain('local-secrets2.afb');
      expect(result.valid).toBe(false);
      expect(result.apex).toBe(false);
      expect(result.reason).toBe('suffix');
      expect(result.tld).toBe('afb');
    });

    it('rejects a common TLD typo (.con)', () => {
      const result = analyzeDomain('acme.con');
      expect(result.valid).toBe(false);
      expect(result.reason).toBe('suffix');
      expect(result.tld).toBe('con');
    });

    it('accepts a real but less-common TLD (.travel)', () => {
      const result = analyzeDomain('acme.travel');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(true);
      expect(result.tld).toBe('travel');
    });
  });

  describe('alignment with addDomainRequestSchema', () => {
    it('accepts an underscore in an interior label (schema allows "_")', () => {
      const result = analyzeDomain('my_app.acme.com');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(false);
      expect(result.subdomain).toBe('my_app');
      expect(result.registrable).toBe('acme.com');
    });

    it('accepts a punycode TLD (xn--p1ai)', () => {
      const result = analyzeDomain('acme.xn--p1ai');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(true);
      expect(result.registrable).toBe('acme.xn--p1ai');
      expect(result.tld).toBe('xn--p1ai');
    });

    it('still rejects a purely-numeric last label', () => {
      const result = analyzeDomain('acme.123');
      expect(result.valid).toBe(false);
      expect(result.reason).toBe('suffix');
    });
  });

  describe('cleaning', () => {
    it('strips scheme, path, and lowercases', () => {
      const result = analyzeDomain('HTTP://Secrets.Acme.COM/foo/bar');
      expect(result.full).toBe('secrets.acme.com');
      expect(result.valid).toBe(true);
      expect(result.apex).toBe(false);
    });

    it('strips a trailing dot', () => {
      const result = analyzeDomain('acme.com.');
      expect(result.full).toBe('acme.com');
      expect(result.apex).toBe(true);
    });
  });

  describe('malformed input', () => {
    it('rejects a label starting with a hyphen', () => {
      const result = analyzeDomain('-acme.com');
      expect(result.valid).toBe(false);
      expect(result.reason).toBe('malformed');
    });

    it('rejects a label ending with a hyphen', () => {
      const result = analyzeDomain('acme-.com');
      expect(result.reason).toBe('malformed');
    });

    it('rejects consecutive dots', () => {
      const result = analyzeDomain('acme..com');
      expect(result.reason).toBe('malformed');
    });

    it('rejects an embedded space', () => {
      const result = analyzeDomain('ac me.com');
      expect(result.reason).toBe('malformed');
    });
  });
});
