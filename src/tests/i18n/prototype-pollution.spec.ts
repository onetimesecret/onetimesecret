// src/tests/i18n/prototype-pollution.spec.ts

/**
 * Prototype Pollution Prevention Tests
 *
 * These tests verify that the i18n module's merge functions
 * are protected against prototype pollution attacks (CWE-1321).
 *
 * @see https://owasp.org/www-community/attacks/Prototype_Pollution
 * @see https://cwe.mitre.org/data/definitions/1321.html
 */

import { createCompatibilityLayer } from '@/i18n';

describe('Prototype Pollution Prevention', () => {
  // Save original Object.prototype state
  // Note: Object.prototype properties are non-enumerable, so we use
  // getOwnPropertyNames() instead of spread syntax or Object.keys()
  const originalPrototypeProperties = Object.getOwnPropertyNames(Object.prototype);

  afterEach(() => {
    // Clean up any pollution that might have occurred
    // @ts-expect-error - Testing prototype pollution
    delete Object.prototype.isAdmin;
    // @ts-expect-error - Testing prototype pollution
    delete Object.prototype.polluted;
    // @ts-expect-error - Testing prototype pollution
    delete Object.prototype.malicious;
  });

  describe('createCompatibilityLayer', () => {
    it('should reject __proto__ keys in input', () => {
      const maliciousInput = {
        legitimate: 'value',
        __proto__: {
          isAdmin: true,
        },
      };

      // This should NOT pollute Object.prototype
      createCompatibilityLayer(maliciousInput);

      // Verify no pollution occurred
      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
    });

    it('should reject constructor keys in input', () => {
      const maliciousInput = {
        legitimate: 'value',
        constructor: {
          prototype: {
            polluted: true,
          },
        },
      };

      createCompatibilityLayer(maliciousInput);

      const testObj: Record<string, unknown> = {};
      expect(testObj.polluted).toBeUndefined();
    });

    it('should reject prototype keys in input', () => {
      const maliciousInput = {
        legitimate: 'value',
        prototype: {
          malicious: true,
        },
      };

      createCompatibilityLayer(maliciousInput);

      const testObj: Record<string, unknown> = {};
      expect(testObj.malicious).toBeUndefined();
    });

    it('should still process legitimate keys', () => {
      const input = {
        greeting: 'hello',
        nested: {
          deep: 'value',
        },
      };

      const result = createCompatibilityLayer(input);

      expect(result.greeting).toBe('hello');
      expect(result['nested.deep']).toBe('value');
    });

    it('should reject dangerous keys in nested objects', () => {
      const maliciousInput = {
        web: {
          __proto__: {
            isAdmin: true,
          },
          auth: {
            constructor: {
              prototype: {
                polluted: true,
              },
            },
          },
        },
      };

      createCompatibilityLayer(maliciousInput);

      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(testObj.polluted).toBeUndefined();
    });
  });

  describe('Object.prototype integrity', () => {
    it('should not modify Object.prototype through any attack vector', () => {
      // Multiple attack vectors
      const attacks = [
        { __proto__: { isAdmin: true } },
        { constructor: { prototype: { isAdmin: true } } },
        { prototype: { isAdmin: true } },
        {
          nested: {
            __proto__: { polluted: true },
          },
        },
      ];

      attacks.forEach((attack) => {
        createCompatibilityLayer(attack);
      });

      // Verify Object.prototype is unchanged
      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(testObj.polluted).toBeUndefined();
      expect(Object.getOwnPropertyNames(Object.prototype)).toEqual(originalPrototypeProperties);
    });
  });
});
