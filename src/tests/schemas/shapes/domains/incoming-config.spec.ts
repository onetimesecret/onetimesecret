// src/tests/schemas/shapes/domains/incoming-config.spec.ts
//
// Schema validation tests for the IncomingConfig admin-view shapes
// after the #3095 migration.

import { describe, it, expect } from 'vitest';
import {
  putIncomingConfigPayloadSchema,
  customDomainIncomingConfigSchema,
  domainIncomingRecipientSchema,
  type PutIncomingConfigPayload,
  type CustomDomainIncomingConfig,
} from '@/schemas/shapes/domains/incoming-config';

// -----------------------------------------------------------------------------
// PUT Payload Schema
// -----------------------------------------------------------------------------

describe('putIncomingConfigPayloadSchema', () => {
  const validPayload = {
    enabled: true,
    recipients: [{ email: 'a@example.com', name: 'A' }],
  };

  describe('valid payloads', () => {
    it('accepts enabled + recipients', () => {
      const result = putIncomingConfigPayloadSchema.parse(validPayload);
      expect(result.enabled).toBe(true);
      expect(result.recipients).toEqual([{ email: 'a@example.com', name: 'A' }]);
    });

    it('accepts an empty recipients array (explicit clear)', () => {
      const result = putIncomingConfigPayloadSchema.parse({
        enabled: false,
        recipients: [],
      });
      expect(result.recipients).toEqual([]);
    });

    it('accepts multiple recipients', () => {
      const payload = {
        enabled: true,
        recipients: [
          { email: 'a@example.com', name: 'A' },
          { email: 'b@example.com', name: 'B' },
          { email: 'c@example.com', name: 'C' },
        ],
      };
      const result = putIncomingConfigPayloadSchema.parse(payload);
      expect(result.recipients).toHaveLength(3);
    });
  });

  describe('invalid payloads', () => {
    it('rejects missing enabled', () => {
      expect(() =>
        putIncomingConfigPayloadSchema.parse({ recipients: [] }),
      ).toThrow();
    });

    it('rejects missing recipients', () => {
      expect(() =>
        putIncomingConfigPayloadSchema.parse({ enabled: true }),
      ).toThrow();
    });

    it('rejects enabled as string', () => {
      expect(() =>
        putIncomingConfigPayloadSchema.parse({ enabled: 'true', recipients: [] }),
      ).toThrow();
    });

    it('rejects a recipient with a malformed email', () => {
      expect(() =>
        putIncomingConfigPayloadSchema.parse({
          enabled: true,
          recipients: [{ email: 'not-an-email', name: 'X' }],
        }),
      ).toThrow();
    });

    it('rejects a recipient missing the email field', () => {
      expect(() =>
        putIncomingConfigPayloadSchema.parse({
          enabled: true,
          recipients: [{ name: 'Nameless' }],
        }),
      ).toThrow();
    });

    it('rejects a recipient missing the name field', () => {
      expect(() =>
        putIncomingConfigPayloadSchema.parse({
          enabled: true,
          recipients: [{ email: 'a@example.com' }],
        }),
      ).toThrow();
    });
  });

  describe('type inference', () => {
    it('infers PutIncomingConfigPayload with enabled + recipients', () => {
      const payload: PutIncomingConfigPayload =
        putIncomingConfigPayloadSchema.parse(validPayload);
      const _enabled: boolean = payload.enabled;
      const _recipients: Array<{ email: string; name: string }> = payload.recipients;
      expect(_enabled).toBe(true);
      expect(_recipients).toHaveLength(1);
    });
  });
});

// -----------------------------------------------------------------------------
// Recipient Schema (plaintext admin view)
// -----------------------------------------------------------------------------

describe('domainIncomingRecipientSchema', () => {
  it('accepts a valid {email, name}', () => {
    const result = domainIncomingRecipientSchema.parse({
      email: 'alice@example.com',
      name: 'Alice',
    });
    expect(result.email).toBe('alice@example.com');
    expect(result.name).toBe('Alice');
  });

  it('rejects a malformed email', () => {
    expect(() =>
      domainIncomingRecipientSchema.parse({ email: 'nope', name: 'Alice' }),
    ).toThrow();
  });

  it('rejects missing email', () => {
    expect(() =>
      domainIncomingRecipientSchema.parse({ name: 'Alice' }),
    ).toThrow();
  });

  it('rejects missing name', () => {
    expect(() =>
      domainIncomingRecipientSchema.parse({ email: 'alice@example.com' }),
    ).toThrow();
  });
});

// -----------------------------------------------------------------------------
// Full Response Schema
// -----------------------------------------------------------------------------

describe('customDomainIncomingConfigSchema', () => {
  const validConfig = {
    domain_id: 'domain_123abc',
    enabled: true,
    recipients: [
      { email: 'alice@example.com', name: 'Alice' },
      { email: 'bob@example.com', name: 'Bob' },
    ],
    max_recipients: 20,
    created_at: 1609459200,
    updated_at: 1609545600,
  };

  describe('valid configs', () => {
    it('parses a complete config with timestamps', () => {
      const result = customDomainIncomingConfigSchema.parse(validConfig);
      expect(result.domain_id).toBe('domain_123abc');
      expect(result.enabled).toBe(true);
      expect(result.recipients).toHaveLength(2);
      expect(result.max_recipients).toBe(20);
    });

    it('transforms Unix timestamps to Date objects', () => {
      const result = customDomainIncomingConfigSchema.parse(validConfig);
      expect(result.created_at).toBeInstanceOf(Date);
      expect(result.updated_at).toBeInstanceOf(Date);
      expect((result.created_at as Date).getTime()).toBe(1609459200 * 1000);
    });

    it('accepts null timestamps (unconfigured state)', () => {
      const unconfigured = {
        ...validConfig,
        recipients: [],
        created_at: null,
        updated_at: null,
      };
      const result = customDomainIncomingConfigSchema.parse(unconfigured);
      expect(result.created_at).toBeNull();
      expect(result.updated_at).toBeNull();
    });

    it('accepts undefined timestamps (collapsed to null by nullish transform)', () => {
      const without = {
        domain_id: 'd',
        enabled: false,
        recipients: [],
        max_recipients: 20,
      };
      const result = customDomainIncomingConfigSchema.parse(without);
      expect(result.created_at).toBeNull();
      expect(result.updated_at).toBeNull();
    });

    it('defaults recipients to empty array when missing', () => {
      const config = {
        domain_id: 'domain_123',
        enabled: false,
        max_recipients: 20,
        created_at: null,
        updated_at: null,
      };
      const result = customDomainIncomingConfigSchema.parse(config);
      expect(result.recipients).toEqual([]);
    });
  });

  describe('invalid configs', () => {
    it('rejects missing domain_id', () => {
      const config = { ...validConfig } as Record<string, unknown>;
      delete config.domain_id;
      expect(() => customDomainIncomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects missing enabled', () => {
      const config = { ...validConfig } as Record<string, unknown>;
      delete config.enabled;
      expect(() => customDomainIncomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects non-positive max_recipients', () => {
      expect(() =>
        customDomainIncomingConfigSchema.parse({ ...validConfig, max_recipients: 0 }),
      ).toThrow();
    });

    it('rejects a recipient with malformed email in the array', () => {
      const config = {
        ...validConfig,
        recipients: [{ email: 'not-an-email', name: 'X' }],
      };
      expect(() => customDomainIncomingConfigSchema.parse(config)).toThrow();
    });
  });

  describe('type inference', () => {
    it('infers CustomDomainIncomingConfig with plaintext recipients and nullable dates', () => {
      const config: CustomDomainIncomingConfig =
        customDomainIncomingConfigSchema.parse(validConfig);
      const _domainId: string = config.domain_id;
      const _enabled: boolean = config.enabled;
      const _recipients: Array<{ email: string; name: string }> = config.recipients;
      const _createdAt: Date | null = config.created_at;
      const _updatedAt: Date | null = config.updated_at;

      expect(_domainId).toBeDefined();
      expect(_enabled).toBe(true);
      expect(_recipients).toHaveLength(2);
      expect(_createdAt).toBeInstanceOf(Date);
      expect(_updatedAt).toBeInstanceOf(Date);
    });
  });
});
