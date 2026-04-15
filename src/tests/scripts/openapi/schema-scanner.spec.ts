// src/tests/scripts/openapi/schema-scanner.spec.ts
//
// Tests for schema-scanner.ts functions, specifically:
// - normalizeModelKey(): converts 'models/*' to 'shapes/*'
// - extractVersion(): detects API version from Ruby class names
// - getRegistryForVersion(): returns version-appropriate registry
// - scanSchemas(): integration test for full scanner

import { beforeAll, describe, expect, it } from 'vitest';
import {
  extractVersion,
  normalizeModelKey,
  getRegistryForVersion,
  scanSchemas,
} from '../../../../scripts/openapi/schema-scanner';
import { responseSchemas as v1ResponseSchemas } from '@/schemas/api/v1/responses/registry';
import { responseSchemas as v2ResponseSchemas } from '@/schemas/api/v2/responses/registry';
import { responseSchemas as v3ResponseSchemas } from '@/schemas/api/v3/responses/registry';
import { responseSchemas as internalResponseSchemas } from '@/schemas/api/internal/responses/registry';
import { responseSchemas as incomingResponseSchemas } from '@/schemas/api/incoming/responses/registry';

describe('schema-scanner', () => {
  // ─── normalizeModelKey ─────────────────────────────────────────

  describe('normalizeModelKey', () => {
    it('converts models/secret to shapes/secret', () => {
      expect(normalizeModelKey('models/secret')).toBe('shapes/secret');
    });

    it('converts models/custom-domain to shapes/custom-domain', () => {
      expect(normalizeModelKey('models/custom-domain')).toBe('shapes/custom-domain');
    });

    it('converts models/receipt to shapes/receipt', () => {
      expect(normalizeModelKey('models/receipt')).toBe('shapes/receipt');
    });

    it('leaves shapes/secret unchanged (already normalized)', () => {
      expect(normalizeModelKey('shapes/secret')).toBe('shapes/secret');
    });

    it('leaves shapes/custom-domain unchanged', () => {
      expect(normalizeModelKey('shapes/custom-domain')).toBe('shapes/custom-domain');
    });

    it('handles empty string', () => {
      expect(normalizeModelKey('')).toBe('');
    });

    it('handles keys without prefix', () => {
      expect(normalizeModelKey('secret')).toBe('secret');
    });

    it('does not replace models/ in the middle of a string', () => {
      // Only replaces at the start of the string
      expect(normalizeModelKey('api/models/secret')).toBe('api/models/secret');
    });

    it('handles models/ with no suffix', () => {
      expect(normalizeModelKey('models/')).toBe('shapes/');
    });

    it('handles nested paths under models/', () => {
      expect(normalizeModelKey('models/v3/secret')).toBe('shapes/v3/secret');
    });
  });

  // ─── extractVersion ────────────────────────────────────────────

  describe('extractVersion', () => {
    // Versioned APIs (V1, V2, V3)
    describe('versioned APIs', () => {
      it('extracts v3 from V3::Logic::Secrets::ConcealSecret', () => {
        expect(extractVersion('V3::Logic::Secrets::ConcealSecret')).toBe('v3');
      });

      it('extracts v2 from V2::Logic::Secrets::ListReceipts', () => {
        expect(extractVersion('V2::Logic::Secrets::ListReceipts')).toBe('v2');
      });

      it('extracts v1 from V1::Controllers::Index#status', () => {
        expect(extractVersion('V1::Controllers::Index#status')).toBe('v1');
      });

      it('handles case insensitivity for version prefix', () => {
        expect(extractVersion('v3::Logic::Test')).toBe('v3');
      });
    });

    // Internal API prefixes
    describe('internal API prefixes', () => {
      it('extracts internal from ColonelAPI::Logic::Colonel::GetColonelInfo', () => {
        expect(extractVersion('ColonelAPI::Logic::Colonel::GetColonelInfo')).toBe('internal');
      });

      it('extracts internal from AccountAPI::Logic::Account::GetAccount', () => {
        expect(extractVersion('AccountAPI::Logic::Account::GetAccount')).toBe('internal');
      });

      it('extracts internal from DomainsAPI::Logic::Domains::ListDomains', () => {
        expect(extractVersion('DomainsAPI::Logic::Domains::ListDomains')).toBe('internal');
      });

      it('extracts internal from OrganizationAPI::Logic::Organizations::GetOrg', () => {
        expect(extractVersion('OrganizationAPI::Logic::Organizations::GetOrg')).toBe('internal');
      });

      it('extracts internal from InviteAPI::Logic::Invites::SendInvite', () => {
        expect(extractVersion('InviteAPI::Logic::Invites::SendInvite')).toBe('internal');
      });
    });

    // Incoming API prefix (new feature being tested)
    describe('incoming API prefix', () => {
      it('extracts incoming from Incoming::Logic::GetConfig', () => {
        expect(extractVersion('Incoming::Logic::GetConfig')).toBe('incoming');
      });

      it('extracts incoming from Incoming::Logic::CreateIncomingSecret', () => {
        expect(extractVersion('Incoming::Logic::CreateIncomingSecret')).toBe('incoming');
      });

      it('extracts incoming from Incoming::Logic::ValidateRecipient', () => {
        expect(extractVersion('Incoming::Logic::ValidateRecipient')).toBe('incoming');
      });
    });

    // Important distinction: Incoming in the middle is NOT the incoming API
    describe('Incoming as inner module (not incoming API)', () => {
      it('extracts v3 from V3::Logic::Incoming::GetConfig (NOT incoming)', () => {
        // This is a V3 API with an Incoming submodule, NOT the Incoming API
        expect(extractVersion('V3::Logic::Incoming::GetConfig')).toBe('v3');
      });

      it('extracts v2 from V2::Logic::Incoming::CreateSecret (NOT incoming)', () => {
        expect(extractVersion('V2::Logic::Incoming::CreateSecret')).toBe('v2');
      });
    });

    // Model classes (no version)
    describe('model classes (no version)', () => {
      it('returns null for Onetime::Secret', () => {
        expect(extractVersion('Onetime::Secret')).toBeNull();
      });

      it('returns null for Onetime::CustomDomain', () => {
        expect(extractVersion('Onetime::CustomDomain')).toBeNull();
      });

      it('returns null for Onetime::Customer', () => {
        expect(extractVersion('Onetime::Customer')).toBeNull();
      });

      it('returns null for empty string', () => {
        expect(extractVersion('')).toBeNull();
      });

      it('returns null for plain class name without namespace', () => {
        expect(extractVersion('Secret')).toBeNull();
      });
    });
  });

  // ─── getRegistryForVersion ─────────────────────────────────────

  describe('getRegistryForVersion', () => {
    it('returns v1 registry for v1', () => {
      expect(getRegistryForVersion('v1')).toBe(v1ResponseSchemas);
    });

    it('returns v2 registry for v2', () => {
      expect(getRegistryForVersion('v2')).toBe(v2ResponseSchemas);
    });

    it('returns v3 registry for v3', () => {
      expect(getRegistryForVersion('v3')).toBe(v3ResponseSchemas);
    });

    it('returns internal registry for internal', () => {
      expect(getRegistryForVersion('internal')).toBe(internalResponseSchemas);
    });

    it('returns incoming registry for incoming', () => {
      expect(getRegistryForVersion('incoming')).toBe(incomingResponseSchemas);
    });

    it('falls back to v3 for null version', () => {
      expect(getRegistryForVersion(null)).toBe(v3ResponseSchemas);
    });

    it('falls back to v3 for unknown version', () => {
      expect(getRegistryForVersion('v99')).toBe(v3ResponseSchemas);
    });
  });

  // ─── scanSchemas integration ───────────────────────────────────

  describe('scanSchemas integration', () => {
    // Cache scanSchemas() result to avoid repeated filesystem/glob scans
    // and Prism parsing across multiple tests.
    let scanResult: Awaited<ReturnType<typeof scanSchemas>>;

    beforeAll(async () => {
      scanResult = await scanSchemas();
    });

    it('returns zero broken entries (all SCHEMA constants resolve)', () => {
      const result = scanResult;

      // The scanner should find entries
      expect(result.entries.length).toBeGreaterThan(0);

      // Critical assertion: no broken entries
      // If this fails, a SCHEMA constant references a key not in the registry
      if (result.broken.length > 0) {
        const brokenDetails = result.broken.map(
          e => `${e.className}: model=${e.schema.model}, response=${e.schema.response}, request=${e.schema.request}`
        );
        throw new Error(`Found ${result.broken.length} broken schema entries:\n${brokenDetails.join('\n')}`);
      }

      expect(result.broken).toHaveLength(0);
    });

    it('finds covered entries for V3 API handlers', () => {
      const result = scanResult;

      // Should have covered entries
      expect(result.covered.length).toBeGreaterThan(0);

      // Verify we found entries from V3 API
      const classNames = result.covered.map(e => e.className);

      // Check for V3 entries
      const hasV3 = classNames.some(name => name.startsWith('V3::'));
      expect(hasV3).toBe(true);
    });

    it('correctly classifies model entries', () => {
      const result = scanResult;

      // Find model entries (from lib/onetime/models/)
      const modelEntries = result.entries.filter(
        e => e.filePath.startsWith('lib/onetime/models/')
      );

      // All model entries should be covered (valid model keys)
      for (const entry of modelEntries) {
        const isCovered = result.covered.includes(entry);
        if (!isCovered) {
          throw new Error(
            `Model entry ${entry.className} with schema.model=${entry.schema.model} should be covered`
          );
        }
      }
    });

    it('scanSchemas result structure is valid', () => {
      const result = scanResult;

      // Verify result structure
      expect(result).toHaveProperty('entries');
      expect(result).toHaveProperty('covered');
      expect(result).toHaveProperty('broken');
      expect(result).toHaveProperty('uncoveredHandlers');
      expect(result).toHaveProperty('uncoveredModels');

      // Arrays should be arrays
      expect(Array.isArray(result.entries)).toBe(true);
      expect(Array.isArray(result.covered)).toBe(true);
      expect(Array.isArray(result.broken)).toBe(true);
      expect(Array.isArray(result.uncoveredHandlers)).toBe(true);
      expect(Array.isArray(result.uncoveredModels)).toBe(true);

      // Covered + broken should equal entries (partitioned)
      expect(result.covered.length + result.broken.length).toBe(result.entries.length);
    });
  });

  // ─── Model key normalization in validation flow ────────────────

  describe('model key normalization in validation flow', () => {
    it('models/* keys are normalized to shapes/* and resolve correctly', async () => {
      // This tests the actual behavior: Ruby declares 'models/secret',
      // scanner normalizes to 'shapes/secret', which exists in shapeSchemas
      const result = await scanSchemas();

      // Find entries with model keys that use the 'models/' prefix
      const modelEntries = result.entries.filter(e => e.schema.model?.startsWith('models/'));

      // Ensure this test cannot pass vacuously: we must observe at least one
      // Ruby model key that requires normalization.
      expect(modelEntries.length).toBeGreaterThan(0);

      for (const entry of modelEntries) {
        const normalizedModelKey = normalizeModelKey(entry.schema.model!);

        // Normalization should convert models/* keys into shapes/* keys.
        expect(normalizedModelKey.startsWith('shapes/')).toBe(true);

        // These entries should be reported as covered by the scanner, which
        // demonstrates that the normalized key matched a known schema.
        const isCovered = result.covered.some(
          c => c.className === entry.className && c.filePath === entry.filePath
        );

        expect(isCovered).toBe(true);
      }
    });
  });
});
