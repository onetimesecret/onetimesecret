// src/tests/i18n/prototype-pollution.spec.ts

/**
 * Prototype Pollution Prevention Tests
 *
 * These tests verify that the i18n module's merge functions
 * are protected against prototype pollution attacks (CWE-1321).
 *
 * Defense-in-depth coverage for all guard points:
 * 1. deepMerge() function - recursive merge with guards
 * 2. Structured file merge path - files with web/email structure
 * 3. Flat file merge path - uncategorized.json direct assignment
 * 4. createCompatibilityLayer() - flattening with guards
 *
 * @see https://owasp.org/www-community/attacks/Prototype_Pollution
 * @see https://cwe.mitre.org/data/definitions/1321.html
 */

import {
  createCompatibilityLayer,
  deepMerge,
  DANGEROUS_KEYS,
  mergeStructuredContent,
  mergeFlatContent,
} from '@/i18n';

describe('Prototype Pollution Prevention', () => {
  // Save original Object.prototype state
  // Note: Object.prototype properties are non-enumerable, so we use
  // getOwnPropertyNames() instead of spread syntax or Object.keys()
  const originalPrototypeProperties = Object.getOwnPropertyNames(Object.prototype);

  afterEach(() => {
    // Clean up known attack vectors (explicit for security test documentation)
    const knownAttackVectors = [
      'isAdmin',
      'polluted',
      'malicious',
      'injected',
      'deepNested',
      'globalAdmin',
      'deepAttack',
      'veryDeep',
      'a',
      'b',
      'c',
      'attack1',
      'attack2',
      'attack3',
    ];
    knownAttackVectors.forEach((prop) => {
      // @ts-expect-error - Intentional cleanup of prototype pollution
      delete Object.prototype[prop];
    });

    // Dynamic verification: catch any unexpected prototype pollution
    const currentProps = Object.getOwnPropertyNames(Object.prototype);
    const unexpected = currentProps.filter((p) => !originalPrototypeProperties.includes(p));
    if (unexpected.length > 0) {
      // Clean up unexpected pollution
      unexpected.forEach((prop) => {
        // @ts-expect-error - Cleanup unexpected pollution
        delete Object.prototype[prop];
      });
      throw new Error(`Unexpected prototype pollution detected: ${unexpected.join(', ')}`);
    }
  });

  describe('DANGEROUS_KEYS constant', () => {
    it('should contain all prototype pollution attack vectors', () => {
      expect(DANGEROUS_KEYS.has('__proto__')).toBe(true);
      expect(DANGEROUS_KEYS.has('constructor')).toBe(true);
      expect(DANGEROUS_KEYS.has('prototype')).toBe(true);
    });

    it('should not block legitimate keys', () => {
      expect(DANGEROUS_KEYS.has('web')).toBe(false);
      expect(DANGEROUS_KEYS.has('email')).toBe(false);
      expect(DANGEROUS_KEYS.has('auth')).toBe(false);
      expect(DANGEROUS_KEYS.has('normal_key')).toBe(false);
    });
  });

  describe('deepMerge() function', () => {
    it('should merge objects normally with legitimate keys', () => {
      const target = { a: 1, nested: { x: 10 } };
      const source = { b: 2, nested: { y: 20 } };

      const result = deepMerge(target, source);

      expect(result.a).toBe(1);
      expect(result.b).toBe(2);
      expect(result.nested.x).toBe(10);
      expect(result.nested.y).toBe(20);
    });

    it('should reject __proto__ keys at top level', () => {
      const target = {};
      const source = {
        legitimate: 'value',
        __proto__: { isAdmin: true },
      };

      deepMerge(target, source);

      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(target).toHaveProperty('legitimate', 'value');
    });

    it('should reject constructor keys at top level', () => {
      const target = {};
      const source = {
        legitimate: 'value',
        constructor: { prototype: { polluted: true } },
      };

      deepMerge(target, source);

      const testObj: Record<string, unknown> = {};
      expect(testObj.polluted).toBeUndefined();
      expect(target).toHaveProperty('legitimate', 'value');
    });

    it('should reject prototype keys at top level', () => {
      const target = {};
      const source = {
        legitimate: 'value',
        prototype: { malicious: true },
      };

      deepMerge(target, source);

      const testObj: Record<string, unknown> = {};
      expect(testObj.malicious).toBeUndefined();
      expect(target).toHaveProperty('legitimate', 'value');
    });

    it('should reject dangerous keys in nested objects', () => {
      const target = { web: {} };
      const source = {
        web: {
          auth: { login: 'Login' },
          __proto__: { isAdmin: true },
        },
      };

      deepMerge(target, source);

      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect((target as any).web.auth.login).toBe('Login');
    });

    it('should reject dangerous keys at multiple nesting levels', () => {
      const target = {};
      const source = {
        level1: {
          level2: {
            level3: {
              __proto__: { deepNested: true },
              constructor: { prototype: { injected: true } },
              legitimate: 'deep value',
            },
          },
        },
      };

      deepMerge(target, source);

      const testObj: Record<string, unknown> = {};
      expect(testObj.deepNested).toBeUndefined();
      expect(testObj.injected).toBeUndefined();
      expect((target as any).level1.level2.level3.legitimate).toBe('deep value');
    });

    it('should skip inherited properties from source', () => {
      const proto = { inherited: 'should not copy' };
      const source = Object.create(proto);
      source.ownProperty = 'should copy';

      const target = {};
      deepMerge(target, source);

      expect(target).toHaveProperty('ownProperty', 'should copy');
      expect(target).not.toHaveProperty('inherited');
    });

    it('should handle arrays without recursing into them', () => {
      const target = {};
      const source = {
        items: ['a', 'b', 'c'],
        nested: { array: [1, 2, 3] },
      };

      deepMerge(target, source);

      expect((target as any).items).toEqual(['a', 'b', 'c']);
      expect((target as any).nested.array).toEqual([1, 2, 3]);
    });

    it('should handle null values correctly', () => {
      const target = { existing: 'value' };
      const source = { nullValue: null, existing: 'updated' };

      deepMerge(target, source);

      expect((target as any).nullValue).toBeNull();
      expect((target as any).existing).toBe('updated');
    });
  });

  describe('Structured file merge path (mergeStructuredContent)', () => {
    /**
     * Tests the real mergeStructuredContent() function exported from i18n.ts.
     * This function handles files with "web" or "email" structure.
     */

    it('should merge valid web/email structured content', () => {
      const messages: Record<string, any> = {};
      const content = {
        web: { auth: { login: 'Login', logout: 'Logout' } },
        email: { welcome: { subject: 'Welcome!' } },
      };

      mergeStructuredContent(messages, content);

      expect(messages.web.auth.login).toBe('Login');
      expect(messages.email.welcome.subject).toBe('Welcome!');
    });

    it('should reject __proto__ as top-level key in structured file', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        web: { auth: { login: 'Login' } },
        __proto__: { isAdmin: true },
      };

      mergeStructuredContent(messages, maliciousContent);

      // Verify no prototype pollution occurred
      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(messages.web.auth.login).toBe('Login');
      // Note: messages.__proto__ always exists (it's the prototype accessor)
      // The key test is that Object.prototype wasn't polluted
      expect(Object.hasOwn(messages, '__proto__')).toBe(false);
    });

    it('should reject constructor as top-level key in structured file', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        web: { dashboard: 'Dashboard' },
        constructor: { prototype: { polluted: true } },
      };

      mergeStructuredContent(messages, maliciousContent);

      // Verify no prototype pollution occurred
      const testObj: Record<string, unknown> = {};
      expect(testObj.polluted).toBeUndefined();
      // Note: messages.constructor always exists (inherited from Object.prototype)
      // The key test is that Object.prototype wasn't polluted
      expect(Object.hasOwn(messages, 'constructor')).toBe(false);
    });

    it('should reject prototype as top-level key in structured file', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        email: { notification: 'You have mail' },
        prototype: { malicious: true },
      };

      mergeStructuredContent(messages, maliciousContent);

      const testObj: Record<string, unknown> = {};
      expect(testObj.malicious).toBeUndefined();
      expect(messages.prototype).toBeUndefined();
    });

    it('should handle mixed legitimate and dangerous top-level keys', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        web: { auth: { login: 'Login' } },
        __proto__: { attack1: true },
        email: { welcome: 'Welcome' },
        constructor: { attack2: true },
        prototype: { attack3: true },
      };

      mergeStructuredContent(messages, maliciousContent);

      const testObj: Record<string, unknown> = {};
      expect(testObj.attack1).toBeUndefined();
      expect(testObj.attack2).toBeUndefined();
      expect(testObj.attack3).toBeUndefined();
      expect(messages.web.auth.login).toBe('Login');
      expect(messages.email.welcome).toBe('Welcome');
    });

    it('should still block dangerous keys nested within web/email', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        web: {
          __proto__: { isAdmin: true },
          auth: { login: 'Login' },
        },
      };

      mergeStructuredContent(messages, maliciousContent);

      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(messages.web.auth.login).toBe('Login');
    });
  });

  describe('Flat file merge path (mergeFlatContent)', () => {
    /**
     * Tests the real mergeFlatContent() function exported from i18n.ts.
     * This function handles flat files like uncategorized.json.
     */

    it('should merge valid flat content', () => {
      const messages: Record<string, any> = {};
      const content = {
        greeting: 'Hello',
        farewell: 'Goodbye',
        nested: { key: 'value' },
      };

      mergeFlatContent(messages, content);

      expect(messages.greeting).toBe('Hello');
      expect(messages.farewell).toBe('Goodbye');
      expect(messages.nested.key).toBe('value');
    });

    it('should reject __proto__ key in flat file', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        greeting: 'Hello',
        __proto__: { isAdmin: true },
      };

      mergeFlatContent(messages, maliciousContent);

      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(messages.greeting).toBe('Hello');
    });

    it('should reject constructor key in flat file', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        greeting: 'Hello',
        constructor: { prototype: { polluted: true } },
      };

      mergeFlatContent(messages, maliciousContent);

      const testObj: Record<string, unknown> = {};
      expect(testObj.polluted).toBeUndefined();
      expect(messages.greeting).toBe('Hello');
    });

    it('should reject prototype key in flat file', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        greeting: 'Hello',
        prototype: { malicious: true },
      };

      mergeFlatContent(messages, maliciousContent);

      const testObj: Record<string, unknown> = {};
      expect(testObj.malicious).toBeUndefined();
      expect(messages.greeting).toBe('Hello');
    });

    it('should handle all dangerous keys together', () => {
      const messages: Record<string, any> = {};
      const maliciousContent = {
        legitimate: 'value',
        __proto__: { a: 1 },
        constructor: { b: 2 },
        prototype: { c: 3 },
      };

      mergeFlatContent(messages, maliciousContent);

      expect(Object.keys(messages)).toEqual(['legitimate']);
      expect(messages.legitimate).toBe('value');
    });
  });

  describe('Integration test: malicious locale file loading', () => {
    /**
     * Tests the complete locale loading pipeline using the real exported
     * mergeStructuredContent and mergeFlatContent functions from i18n.ts.
     * This verifies end-to-end defense across all merge paths.
     */
    function simulateLocaleLoading(
      localeFiles: Array<{ path: string; content: Record<string, any> }>
    ): Record<string, any> {
      const messages: Record<string, any> = {};

      for (const file of localeFiles) {
        // Extract locale from path
        const match = file.path.match(/\/locales\/([^\/]+)\//);
        if (!match) continue;

        const locale = match[1];
        const content = file.content;

        if (!messages[locale]) {
          messages[locale] = {};
        }

        // Check if structured or flat file (matches i18n.ts logic)
        const hasStructuredKeys = 'web' in content || 'email' in content;

        if (hasStructuredKeys) {
          // Use the real production function
          mergeStructuredContent(messages[locale], content);
        } else {
          // Use the real production function
          mergeFlatContent(messages[locale], content);
        }
      }

      return messages;
    }

    it('should safely load multiple locale files with mixed attack vectors', () => {
      const maliciousFiles = [
        {
          path: '/src/locales/en/auth.json',
          content: {
            web: {
              auth: { login: 'Login', logout: 'Logout' },
              __proto__: { isAdmin: true },
            },
            __proto__: { globalAdmin: true },
          },
        },
        {
          path: '/src/locales/en/uncategorized.json',
          content: {
            greeting: 'Hello',
            __proto__: { polluted: true },
            constructor: { prototype: { injected: true } },
          },
        },
        {
          path: '/src/locales/en/email.json',
          content: {
            email: { welcome: { subject: 'Welcome!' } },
            prototype: { malicious: true },
          },
        },
      ];

      const messages = simulateLocaleLoading(maliciousFiles);

      // Verify no prototype pollution occurred
      const testObj: Record<string, unknown> = {};
      expect(testObj.isAdmin).toBeUndefined();
      expect(testObj.globalAdmin).toBeUndefined();
      expect(testObj.polluted).toBeUndefined();
      expect(testObj.injected).toBeUndefined();
      expect(testObj.malicious).toBeUndefined();

      // Verify legitimate content was loaded
      expect(messages.en.web.auth.login).toBe('Login');
      expect(messages.en.greeting).toBe('Hello');
      expect(messages.en.email.welcome.subject).toBe('Welcome!');
    });

    it('should handle deeply nested attack payloads', () => {
      const deeplyNestedAttack = [
        {
          path: '/src/locales/en/complex.json',
          content: {
            web: {
              settings: {
                account: {
                  security: {
                    __proto__: { deepAttack: true },
                    mfa: {
                      enabled: 'MFA Enabled',
                      constructor: { prototype: { veryDeep: true } },
                    },
                  },
                },
              },
            },
          },
        },
      ];

      const messages = simulateLocaleLoading(deeplyNestedAttack);

      const testObj: Record<string, unknown> = {};
      expect(testObj.deepAttack).toBeUndefined();
      expect(testObj.veryDeep).toBeUndefined();
      expect(messages.en.web.settings.account.security.mfa.enabled).toBe('MFA Enabled');
    });

    it('should maintain Object.prototype integrity after loading', () => {
      const attackFiles = [
        {
          path: '/src/locales/en/attack1.json',
          content: { web: { __proto__: { a: 1 } } },
        },
        {
          path: '/src/locales/en/attack2.json',
          content: { constructor: { prototype: { b: 2 } } },
        },
        {
          path: '/src/locales/en/attack3.json',
          content: { prototype: { c: 3 } },
        },
      ];

      simulateLocaleLoading(attackFiles);

      expect(Object.getOwnPropertyNames(Object.prototype)).toEqual(originalPrototypeProperties);
    });

    it('should handle empty and null content safely', () => {
      const edgeCaseFiles = [
        {
          path: '/src/locales/en/empty.json',
          content: {},
        },
        {
          path: '/src/locales/en/withNulls.json',
          // Flat file (no web/email keys) to test null handling
          content: {
            nullKey: null,
            validKey: 'value',
          },
        },
      ];

      const messages = simulateLocaleLoading(edgeCaseFiles);

      expect(messages.en).toBeDefined();
      expect(messages.en.nullKey).toBeNull();
      expect(messages.en.validKey).toBe('value');
    });
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
