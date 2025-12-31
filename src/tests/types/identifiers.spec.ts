// src/tests/types/identifiers.spec.ts

/**
 * Unit tests for the Opaque Identifier Pattern (ExtId/ObjId branded types)
 *
 * @see src/types/identifiers.ts
 * @see docs/IDENTIFIER-REVIEW-CHECKLIST.md
 */

import {
  toObjId,
  toExtId,
  looksLikeExtId,
  looksLikeObjId,
  buildEntityPath,
  buildApiPath,
  buildApiPathWithAction,
  objIdSchema,
  extIdSchema,
  lenientObjIdSchema,
  lenientExtIdSchema,
  assertExtId,
  type ObjId,
  type ExtId,
} from '@/types/identifiers';
import { describe, expect, it, vi } from 'vitest';

describe('Opaque Identifier Pattern', () => {
  describe('toObjId constructor', () => {
    it('creates ObjId from string', () => {
      const id = toObjId('abc123');
      expect(id).toBe('abc123');
      // TypeScript ensures type safety - this is a branded type
    });

    it('preserves string value at runtime', () => {
      const raw = 'internal-uuid-here';
      const id = toObjId(raw);
      expect(typeof id).toBe('string');
      expect(id).toBe(raw);
    });
  });

  describe('toExtId constructor', () => {
    it('creates ExtId from string', () => {
      const id = toExtId('on8a7b9c');
      expect(id).toBe('on8a7b9c');
    });

    it('preserves string value at runtime', () => {
      const raw = 'cd4f2e1a';
      const id = toExtId(raw);
      expect(typeof id).toBe('string');
      expect(id).toBe(raw);
    });
  });

  describe('looksLikeExtId type guard', () => {
    it('recognizes organization ExtIds (on prefix)', () => {
      expect(looksLikeExtId('on8a7b9c')).toBe(true);
      expect(looksLikeExtId('on123456')).toBe(true);
    });

    it('recognizes domain ExtIds (cd prefix)', () => {
      expect(looksLikeExtId('cd4f2e1a')).toBe(true);
      expect(looksLikeExtId('cdabcdef')).toBe(true);
    });

    it('recognizes customer ExtIds (ur prefix)', () => {
      expect(looksLikeExtId('ur7d9c3b')).toBe(true);
      expect(looksLikeExtId('ur999888')).toBe(true);
    });

    it('recognizes secret ExtIds (se prefix)', () => {
      expect(looksLikeExtId('se123abc')).toBe(true);
    });

    it('recognizes metadata ExtIds (md prefix)', () => {
      expect(looksLikeExtId('md456def')).toBe(true);
    });

    it('rejects strings without recognized prefix', () => {
      expect(looksLikeExtId('abc123')).toBe(false);
      expect(looksLikeExtId('xyz789')).toBe(false);
    });

    it('rejects UUIDs (internal IDs)', () => {
      expect(looksLikeExtId('550e8400-e29b-41d4-a716-446655440000')).toBe(false);
    });

    it('handles edge cases', () => {
      expect(looksLikeExtId('')).toBe(false);
      expect(looksLikeExtId('on')).toBe(false); // prefix only, no content
      expect(looksLikeExtId('cd')).toBe(false);
      // @ts-expect-error - testing runtime behavior with wrong type
      expect(looksLikeExtId(null)).toBe(false);
      // @ts-expect-error - testing runtime behavior with wrong type
      expect(looksLikeExtId(undefined)).toBe(false);
    });
  });

  describe('looksLikeObjId type guard', () => {
    it('recognizes UUID format with dashes', () => {
      expect(looksLikeObjId('550e8400-e29b-41d4-a716-446655440000')).toBe(true);
      expect(looksLikeObjId('f47ac10b-58cc-4372-a567-0e02b2c3d479')).toBe(true);
    });

    it('recognizes UUID format without dashes', () => {
      expect(looksLikeObjId('550e8400e29b41d4a716446655440000')).toBe(true);
    });

    it('recognizes hex strings (Redis-style IDs)', () => {
      expect(looksLikeObjId('1234567890abcdef')).toBe(true); // 16 chars
      expect(looksLikeObjId('1234567890abcdef12345678')).toBe(true); // 24 chars
    });

    it('rejects ExtId-like strings', () => {
      expect(looksLikeObjId('on8a7b9c')).toBe(false);
      expect(looksLikeObjId('cd4f2e1a')).toBe(false);
    });

    it('handles edge cases', () => {
      expect(looksLikeObjId('')).toBe(false);
      expect(looksLikeObjId('short')).toBe(false);
      // @ts-expect-error - testing runtime behavior with wrong type
      expect(looksLikeObjId(null)).toBe(false);
    });
  });

  describe('buildEntityPath', () => {
    it('builds organization path', () => {
      const extid = toExtId('on8a7b9c');
      expect(buildEntityPath('org', extid)).toBe('/org/on8a7b9c');
    });

    it('builds domain path', () => {
      const extid = toExtId('cd4f2e1a');
      expect(buildEntityPath('domain', extid)).toBe('/domains/cd4f2e1a');
    });

    it('builds secret path', () => {
      const extid = toExtId('se123abc');
      expect(buildEntityPath('secret', extid)).toBe('/secret/se123abc');
    });

    it('builds customer path', () => {
      const extid = toExtId('ur7d9c3b');
      expect(buildEntityPath('customer', extid)).toBe('/customer/ur7d9c3b');
    });

    // Type safety test - these would fail at compile time if uncommented:
    // it('rejects ObjId at compile time', () => {
    //   const objid = toObjId('internal-id');
    //   buildEntityPath('org', objid); // TypeScript error!
    // });
  });

  describe('buildApiPath', () => {
    it('builds organization API path', () => {
      const extid = toExtId('on8a7b9c');
      expect(buildApiPath('org', extid)).toBe('/api/organizations/on8a7b9c');
    });

    it('builds domain API path', () => {
      const extid = toExtId('cd4f2e1a');
      expect(buildApiPath('domain', extid)).toBe('/api/domains/cd4f2e1a');
    });

    it('builds secret API path', () => {
      const extid = toExtId('se123abc');
      expect(buildApiPath('secret', extid)).toBe('/api/secrets/se123abc');
    });
  });

  describe('buildApiPathWithAction', () => {
    it('builds path with action suffix', () => {
      const extid = toExtId('on8a7b9c');
      expect(buildApiPathWithAction('org', extid, 'members')).toBe(
        '/api/organizations/on8a7b9c/members'
      );
    });

    it('builds domain verification path', () => {
      const extid = toExtId('cd4f2e1a');
      expect(buildApiPathWithAction('domain', extid, 'verify')).toBe(
        '/api/domains/cd4f2e1a/verify'
      );
    });
  });

  describe('Zod schemas', () => {
    describe('lenientObjIdSchema', () => {
      it('accepts any string and outputs branded ObjId', () => {
        const result = lenientObjIdSchema.parse('any-string-here');
        expect(result).toBe('any-string-here');
        // TypeScript knows this is ObjId
      });

      it('rejects non-strings', () => {
        expect(() => lenientObjIdSchema.parse(123)).toThrow();
        expect(() => lenientObjIdSchema.parse(null)).toThrow();
      });
    });

    describe('lenientExtIdSchema', () => {
      it('accepts any string and outputs branded ExtId', () => {
        const result = lenientExtIdSchema.parse('on8a7b9c');
        expect(result).toBe('on8a7b9c');
        // TypeScript knows this is ExtId
      });

      it('also accepts non-prefixed strings during migration', () => {
        const result = lenientExtIdSchema.parse('random-string');
        expect(result).toBe('random-string');
      });
    });

    describe('objIdSchema (strict)', () => {
      it('accepts internal ID formats', () => {
        const result = objIdSchema.parse('550e8400-e29b-41d4-a716-446655440000');
        expect(result).toBe('550e8400-e29b-41d4-a716-446655440000');
      });

      it('rejects ExtId-like strings', () => {
        expect(() => objIdSchema.parse('on8a7b9c')).toThrow();
        expect(() => objIdSchema.parse('cd4f2e1a')).toThrow();
      });
    });

    describe('extIdSchema (strict)', () => {
      it('accepts valid ExtId formats', () => {
        const result = extIdSchema.parse('on8a7b9c');
        expect(result).toBe('on8a7b9c');
      });

      it('rejects internal ID formats', () => {
        expect(() => extIdSchema.parse('550e8400-e29b-41d4-a716-446655440000')).toThrow();
        expect(() => extIdSchema.parse('random-string')).toThrow();
      });
    });
  });

  describe('assertExtId', () => {
    it('does not throw for valid ExtIds', () => {
      expect(() => assertExtId('on8a7b9c')).not.toThrow();
      expect(() => assertExtId('cd4f2e1a')).not.toThrow();
    });

    it('logs warning for invalid ExtIds', () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      // In non-DEV mode, it logs but doesn't throw
      assertExtId('invalid-id');

      expect(consoleSpy).toHaveBeenCalled();
      consoleSpy.mockRestore();
    });

    it('includes context in warning message', () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      assertExtId('bad-id', 'TestComponent');

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('[TestComponent]')
      );
      consoleSpy.mockRestore();
    });
  });

  describe('Type Safety Documentation', () => {
    /**
     * These tests document the compile-time type safety.
     * The commented code would fail TypeScript compilation.
     */

    it('documents that ObjId and ExtId are incompatible', () => {
      const objid: ObjId = toObjId('internal');
      const extid: ExtId = toExtId('on123');

      // These would cause TypeScript errors:
      // const badExtId: ExtId = objid; // Error!
      // const badObjId: ObjId = extid; // Error!

      // But they're both strings at runtime
      expect(typeof objid).toBe('string');
      expect(typeof extid).toBe('string');
    });

    it('documents that buildEntityPath requires ExtId', () => {
      // This compiles:
      const extid = toExtId('on123');
      const path = buildEntityPath('org', extid);
      expect(path).toBe('/org/on123');

      // This would NOT compile:
      // const objid = toObjId('internal');
      // buildEntityPath('org', objid); // TypeScript error!
    });

    it('documents migration path from unbranded to branded', () => {
      // During migration, use lenient schemas that accept any string
      const apiResponse = { id: 'some-id', extid: 'on123' };

      const parsed = {
        id: lenientObjIdSchema.parse(apiResponse.id),
        extid: lenientExtIdSchema.parse(apiResponse.extid),
      };

      // Now parsed.id is ObjId and parsed.extid is ExtId
      // TypeScript enforces correct usage from here on
      expect(typeof parsed.id).toBe('string');
      expect(typeof parsed.extid).toBe('string');
    });
  });
});
