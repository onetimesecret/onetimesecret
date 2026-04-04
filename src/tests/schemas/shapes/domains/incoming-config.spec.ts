// src/tests/schemas/shapes/domains/incoming-config.spec.ts
//
// Schema validation tests for IncomingConfig payload schemas.
// Verifies putIncomingConfigPayloadSchema and patchIncomingConfigPayloadSchema
// correctly validate request payloads.
//
// Coverage:
// 1. PUT schema requires `enabled` boolean
// 2. PATCH schema allows optional `enabled`
// 3. Both schemas reject invalid types
// 4. Response schema parses full config with timestamps

import { describe, it, expect } from 'vitest';
import {
  putIncomingConfigPayloadSchema,
  patchIncomingConfigPayloadSchema,
  customDomainIncomingConfigSchema,
  domainIncomingRecipientSchema,
  type PutIncomingConfigPayload,
  type PatchIncomingConfigPayload,
  type CustomDomainIncomingConfig,
} from '@/schemas/shapes/domains/incoming-config';

// -----------------------------------------------------------------------------
// PUT Payload Schema Tests
// -----------------------------------------------------------------------------

describe('putIncomingConfigPayloadSchema', () => {
  describe('valid payloads', () => {
    it('accepts enabled: true', () => {
      const payload = { enabled: true };
      const result = putIncomingConfigPayloadSchema.parse(payload);
      expect(result.enabled).toBe(true);
    });

    it('accepts enabled: false', () => {
      const payload = { enabled: false };
      const result = putIncomingConfigPayloadSchema.parse(payload);
      expect(result.enabled).toBe(false);
    });
  });

  describe('invalid payloads', () => {
    it('rejects missing enabled field', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({})).toThrow();
    });

    it('rejects enabled as string "true"', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({ enabled: 'true' })).toThrow();
    });

    it('rejects enabled as string "false"', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({ enabled: 'false' })).toThrow();
    });

    it('rejects enabled as number 1', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({ enabled: 1 })).toThrow();
    });

    it('rejects enabled as number 0', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({ enabled: 0 })).toThrow();
    });

    it('rejects enabled as null', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({ enabled: null })).toThrow();
    });

    it('rejects enabled as undefined explicitly', () => {
      expect(() => putIncomingConfigPayloadSchema.parse({ enabled: undefined })).toThrow();
    });
  });

  describe('extra fields', () => {
    it('strips unknown fields (Zod default behavior)', () => {
      const payload = { enabled: true, extra: 'ignored' };
      const result = putIncomingConfigPayloadSchema.parse(payload);
      expect(result).toEqual({ enabled: true });
      expect((result as Record<string, unknown>).extra).toBeUndefined();
    });
  });

  describe('type inference', () => {
    it('infers correct TypeScript type', () => {
      const payload: PutIncomingConfigPayload = putIncomingConfigPayloadSchema.parse({
        enabled: true,
      });

      // Type assertion - would fail compilation if type is wrong
      const _enabled: boolean = payload.enabled;
      expect(_enabled).toBe(true);
    });
  });
});

// -----------------------------------------------------------------------------
// PATCH Payload Schema Tests
// -----------------------------------------------------------------------------

describe('patchIncomingConfigPayloadSchema', () => {
  describe('valid payloads', () => {
    it('accepts enabled: true', () => {
      const result = patchIncomingConfigPayloadSchema.parse({ enabled: true });
      expect(result.enabled).toBe(true);
    });

    it('accepts enabled: false', () => {
      const result = patchIncomingConfigPayloadSchema.parse({ enabled: false });
      expect(result.enabled).toBe(false);
    });

    it('accepts empty object (all fields optional)', () => {
      const result = patchIncomingConfigPayloadSchema.parse({});
      expect(result.enabled).toBeUndefined();
    });
  });

  describe('invalid payloads', () => {
    it('rejects enabled as string', () => {
      expect(() => patchIncomingConfigPayloadSchema.parse({ enabled: 'true' })).toThrow();
    });

    it('rejects enabled as number', () => {
      expect(() => patchIncomingConfigPayloadSchema.parse({ enabled: 1 })).toThrow();
    });
  });

  describe('type inference', () => {
    it('infers enabled as optional boolean', () => {
      const payload: PatchIncomingConfigPayload = patchIncomingConfigPayloadSchema.parse({});

      // enabled should be boolean | undefined
      const _enabled: boolean | undefined = payload.enabled;
      expect(_enabled).toBeUndefined();
    });
  });
});

// -----------------------------------------------------------------------------
// Recipient Schema Tests
// -----------------------------------------------------------------------------

describe('domainIncomingRecipientSchema', () => {
  it('accepts valid recipient with hash and name', () => {
    const recipient = { hash: 'abc123def456', name: 'Alice' };
    const result = domainIncomingRecipientSchema.parse(recipient);
    expect(result.hash).toBe('abc123def456');
    expect(result.name).toBe('Alice');
  });

  it('accepts recipient with empty name', () => {
    const recipient = { hash: 'abc123', name: '' };
    const result = domainIncomingRecipientSchema.parse(recipient);
    expect(result.name).toBe('');
  });

  it('rejects missing hash', () => {
    expect(() => domainIncomingRecipientSchema.parse({ name: 'Alice' })).toThrow();
  });

  it('rejects missing name', () => {
    expect(() => domainIncomingRecipientSchema.parse({ hash: 'abc123' })).toThrow();
  });

  it('rejects empty hash (min length 1)', () => {
    expect(() => domainIncomingRecipientSchema.parse({ hash: '', name: 'Alice' })).toThrow();
  });
});

// -----------------------------------------------------------------------------
// Full Config Response Schema Tests
// -----------------------------------------------------------------------------

describe('customDomainIncomingConfigSchema', () => {
  const validConfig = {
    domain_id: 'domain_123abc',
    enabled: true,
    recipients: [
      { hash: 'hash1', name: 'Alice' },
      { hash: 'hash2', name: 'Bob' },
    ],
    max_recipients: 20,
    created_at: 1609459200, // Unix timestamp
    updated_at: 1609545600, // Unix timestamp
  };

  describe('valid configs', () => {
    it('parses complete config with timestamps', () => {
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
      expect(result.created_at.getTime()).toBe(1609459200 * 1000);
      expect(result.updated_at.getTime()).toBe(1609545600 * 1000);
    });

    it('accepts enabled: false', () => {
      const config = { ...validConfig, enabled: false };
      const result = customDomainIncomingConfigSchema.parse(config);
      expect(result.enabled).toBe(false);
    });

    it('defaults recipients to empty array when missing', () => {
      const config = {
        domain_id: 'domain_123',
        enabled: false,
        max_recipients: 20,
        created_at: 1609459200,
        updated_at: 1609545600,
      };
      const result = customDomainIncomingConfigSchema.parse(config);
      expect(result.recipients).toEqual([]);
    });

    it('accepts empty recipients array', () => {
      const config = { ...validConfig, recipients: [] };
      const result = customDomainIncomingConfigSchema.parse(config);
      expect(result.recipients).toEqual([]);
    });
  });

  describe('invalid configs', () => {
    it('rejects missing domain_id', () => {
      const config = { ...validConfig };
      delete (config as Record<string, unknown>).domain_id;
      expect(() => customDomainIncomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects missing enabled', () => {
      const config = { ...validConfig };
      delete (config as Record<string, unknown>).enabled;
      expect(() => customDomainIncomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects non-positive max_recipients', () => {
      expect(() =>
        customDomainIncomingConfigSchema.parse({ ...validConfig, max_recipients: 0 })
      ).toThrow();
      expect(() =>
        customDomainIncomingConfigSchema.parse({ ...validConfig, max_recipients: -1 })
      ).toThrow();
    });

    it('rejects non-integer max_recipients', () => {
      expect(() =>
        customDomainIncomingConfigSchema.parse({ ...validConfig, max_recipients: 20.5 })
      ).toThrow();
    });

    it('rejects invalid recipient in array', () => {
      const config = {
        ...validConfig,
        recipients: [{ hash: '', name: 'Invalid' }], // empty hash
      };
      expect(() => customDomainIncomingConfigSchema.parse(config)).toThrow();
    });
  });

  describe('type inference', () => {
    it('infers correct TypeScript type', () => {
      const config: CustomDomainIncomingConfig =
        customDomainIncomingConfigSchema.parse(validConfig);

      // Type assertions
      const _domainId: string = config.domain_id;
      const _enabled: boolean = config.enabled;
      const _recipients: Array<{ hash: string; name: string }> = config.recipients;
      const _maxRecipients: number = config.max_recipients;
      const _createdAt: Date = config.created_at;
      const _updatedAt: Date = config.updated_at;

      expect(_domainId).toBeDefined();
      expect(_enabled).toBeDefined();
      expect(_recipients).toBeDefined();
      expect(_maxRecipients).toBeDefined();
      expect(_createdAt).toBeDefined();
      expect(_updatedAt).toBeDefined();
    });
  });
});
