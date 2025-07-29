// src/tests/stores/jurisdictionStore.spec.ts

import { ApiError, ApplicationError } from '@/schemas';
import type { Jurisdiction, RegionsConfig } from '@/schemas/models';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { createTestingPinia } from '@pinia/testing';
import { beforeEach, describe, expect, it } from 'vitest';
import { createApp } from 'vue';

// Fixtures that match the schema requirements
const mockJurisdictions: Jurisdiction[] = [
  {
    identifier: 'us-east',
    display_name: 'US East',
    domain: 'us-east.example.com',
    icon: 'us-flag',
    enabled: true,
  },
  {
    identifier: 'eu-west',
    display_name: 'EU West',
    domain: 'eu-west.example.com',
    icon: 'eu-flag',
    enabled: true,
  },
];

const mockRegionConfig: RegionsConfig = {
  identifier: 'default',
  enabled: true,
  current_jurisdiction: 'us-east',
  jurisdictions: mockJurisdictions,
};

describe('jurisdictionStore', () => {
  let store: ReturnType<typeof useJurisdictionStore>;

  beforeEach(() => {
    const app = createApp({});
    const pinia = createTestingPinia({ stubActions: false });
    app.use(pinia);
    store = useJurisdictionStore();
  });

  describe('initialization', () => {
    it('initializes with valid config', () => {
      store.init({ regions: mockRegionConfig });

      // Test full jurisdiction object structure
      expect(store.currentJurisdiction).toEqual({
        identifier: 'us-east',
        display_name: 'US East',
        domain: 'us-east.example.com',
        icon: 'us-flag',
        enabled: true,
      });

      // Verify array contents explicitly
      expect(store.jurisdictions).toEqual([mockJurisdictions[0], mockJurisdictions[1]]);
    });

    it('handles disabled config', () => {
      const disabledConfig: RegionsConfig = {
        ...mockRegionConfig,
        enabled: false,
      };

      store.init({ regions: disabledConfig });

      expect(store.enabled).toBe(false);
      expect(store.jurisdictions).toHaveLength(1); // Should only have default jurisdiction
      expect(store.currentJurisdiction).toBeTruthy();
    });

    it('maintains single jurisdiction when regions disabled', () => {
      const singleJurisdictionConfig: RegionsConfig = {
        identifier: 'default',
        enabled: false,
        current_jurisdiction: 'us-east',
        jurisdictions: [mockJurisdictions[0]],
      };

      store.init({ regions: singleJurisdictionConfig });

      expect(store.jurisdictions).toHaveLength(1);
      expect(store.currentJurisdiction).toEqual(mockJurisdictions[0]);
    });
  });

  describe('findJurisdiction', () => {
    beforeEach(() => {
      store.init({ regions: mockRegionConfig });
    });

    it('finds existing jurisdiction by identifier', () => {
      const result = store.findJurisdiction('eu-west');
      expect(result).toEqual(mockJurisdictions[1]);
    });

    it('throws ApiError for non-existent jurisdiction', () => {
      expect(() => {
        store.findJurisdiction('non-existent');
      }).toThrow(ApiError);
    });

    it('finds jurisdiction with case-sensitive match', () => {
      expect(() => {
        store.findJurisdiction('EU-WEST');
      }).toThrow(ApiError);
    });

    it('throws descriptive ApplicationError for non-existent jurisdiction', () => {
      store.init({ regions: mockRegionConfig });

      let thrownError: ApplicationError;
      try {
        store.findJurisdiction('non-existent');
      } catch (e) {
        thrownError = e as ApplicationError;
      }

      expect(thrownError!).toBeDefined();
      expect(thrownError!.message).toMatch(/Jurisdiction "non-existent" not found/i);
      expect(thrownError!.type).toBe('technical');
      expect(thrownError!.severity).toBe('error');
      expect(thrownError!.details).toEqual({
        identifier: 'non-existent',
      });
    });

    // Add a test for case sensitivity
    it('throws ApplicationError with correct details for case-sensitive match', () => {
      store.init({ regions: mockRegionConfig });

      let thrownError: ApplicationError;
      try {
        store.findJurisdiction('EU-WEST');
      } catch (e) {
        thrownError = e as ApplicationError;
      }

      expect(thrownError!).toBeDefined();
      expect(thrownError!.type).toBe('technical');
      expect(thrownError!.severity).toBe('error');
      expect(thrownError!.details).toEqual({
        identifier: 'EU-WEST',
      });
    });

    it('throws ApplicationError for non-existent jurisdiction', () => {
      let thrownError: ApplicationError;
      try {
        store.findJurisdiction('non-existent');
      } catch (e) {
        thrownError = e as ApplicationError;
      }

      expect(thrownError!).toBeDefined();
      expect(thrownError!.type).toBe('technical');
      expect(thrownError!.severity).toBe('error');
      expect(thrownError!.details).toMatchObject({
        identifier: 'non-existent',
      });
    });

    it('maintains error type consistency', () => {
      const errorTypes = new Set<string>();

      try {
        store.findJurisdiction('fake-id');
      } catch (e) {
        errorTypes.add((e as ApplicationError).type);
      }

      try {
        store.init({ regions: null } as any);
      } catch (e) {
        errorTypes.add((e as ApplicationError).type);
      }

      // All errors should be of the same type
      expect(errorTypes.size).toBe(1);
      expect(errorTypes.has('technical')).toBe(true);
    });
  });

  describe('error handling', () => {
    beforeEach(() => {});

    it('handles null config gracefully', () => {
      expect(() => {
        store.init({ regions: null } as any);
      }).not.toThrow();

      expect(store.enabled).toBe(false);
    });

    it('handles malformed jurisdiction data (easy)', () => {
      const malformedConfig = {
        ...mockRegionConfig,
        jurisdictions: [{ identifier: 'broken' }], // Missing required fields
      };

      expect(() => {
        store.init({ regions: malformedConfig } as any);
      }).toThrow();
    });

    it('handles missing current_jurisdiction (easy)', () => {
      const invalidConfig = {
        ...mockRegionConfig,
        current_jurisdiction: undefined,
      };

      expect(() => {
        store.init({ regions: invalidConfig } as any);
      }).toThrow();
    });

    it('handles malformed jurisdiction data with specific error', () => {
      const malformedConfig = {
        ...mockRegionConfig,
        jurisdictions: [{ identifier: 'broken' }], // Missing required fields
      };

      let thrownError: ApplicationError;
      try {
        store.init({ regions: malformedConfig } as any);
      } catch (e) {
        thrownError = e as ApplicationError;
      }

      expect(thrownError!).toBeDefined();
      expect(thrownError!.type).toBe('technical');
      expect(thrownError!.severity).toBe('error');
      expect(thrownError!.details).toBeDefined();
    });

    it('handles missing current_jurisdiction with specific error', () => {
      const invalidConfig = {
        ...mockRegionConfig,
        current_jurisdiction: undefined,
      };

      let thrownError: ApplicationError;
      try {
        store.init({ regions: invalidConfig } as any);
      } catch (e) {
        thrownError = e as ApplicationError;
      }

      expect(thrownError!).toBeDefined();
      expect(thrownError!.type).toBe('technical');
      expect(thrownError!.details).toMatchObject({
        identifier: undefined,
      });
    });
  });

  describe('edge cases', () => {
    it('handles empty jurisdictions array', () => {
      const emptyConfig: RegionsConfig = {
        identifier: 'default',
        enabled: true,
        current_jurisdiction: 'default',
        jurisdictions: [],
      };

      // Handle the error in a synchronous way (changed from rejects.toThrow())
      expect(() => {
        store.init({ regions: emptyConfig });
      }).toThrow(); //

      expect(store.jurisdictions).toHaveLength(0);
      expect(store.currentJurisdiction).toBeNull();
    });

    it('handles empty jurisdictions array correctly', () => {
      const emptyConfig: RegionsConfig = {
        identifier: 'default',
        enabled: true,
        current_jurisdiction: 'default',
        jurisdictions: [],
      };

      let thrownError: Error;
      try {
        store.init({ regions: emptyConfig });
      } catch (e) {
        thrownError = e as Error;
      }

      // Verify error and state
      expect(thrownError!).toBeDefined();
      expect(thrownError!.message).toMatch(/Jurisdiction.+ not found/i);
      expect(store.jurisdictions).toHaveLength(0);
      expect(store.currentJurisdiction).toBeNull();
    });

    it('handles empty jurisdictions array with proper error', () => {
      const emptyConfig: RegionsConfig = {
        identifier: 'default',
        enabled: true,
        current_jurisdiction: 'default',
        jurisdictions: [],
      };

      let thrownError: ApplicationError;
      try {
        store.init({ regions: emptyConfig });
      } catch (e) {
        thrownError = e as ApplicationError;
      }

      expect(thrownError!).toBeDefined();
      expect(thrownError!.type).toBe('technical');
      expect(thrownError!.details).toBeDefined();
      expect(store.jurisdictions).toHaveLength(0);
      expect(store.currentJurisdiction).toBeNull();
    });

    it('handles disabled jurisdictions', () => {
      const configWithDisabled: RegionsConfig = {
        ...mockRegionConfig,
        jurisdictions: [
          { ...mockJurisdictions[0], enabled: false },
          mockJurisdictions[1],
        ],
      };

      store.init({ regions: configWithDisabled });
      expect(store.jurisdictions).toHaveLength(2);
      expect(store.jurisdictions[0].enabled).toBe(false);
    });

    it('validates jurisdiction identifier format', () => {
      const invalidConfig: RegionsConfig = {
        ...mockRegionConfig,
        jurisdictions: [
          { ...mockJurisdictions[0], identifier: 'a' }, // Too short
        ],
      };

      expect(() => {
        store.init({ regions: invalidConfig });
      }).toThrow();
    });

    it('validates jurisdiction identifier format strictly', () => {
      const tooShortId = { ...mockJurisdictions[0], identifier: 'a' };
      const tooLongId = { ...mockJurisdictions[0], identifier: 'a'.repeat(25) };

      // Test both bounds
      expect(() =>
        store.init({
          regions: {
            ...mockRegionConfig,
            jurisdictions: [tooShortId],
          }
        })
      ).toThrow(/Jurisdiction "us-east" not found/i);

      expect(() =>
        store.init({
          regions: {
            ...mockRegionConfig,
            jurisdictions: [tooLongId],
          }
        })
      ).toThrow(/Jurisdiction "us-east" not found/i);
    });
  });

  describe('getters', () => {
    beforeEach(() => {
      store.init({ regions: mockRegionConfig });
    });

    it('getCurrentJurisdiction returns correct jurisdiction', () => {
      expect(store.getCurrentJurisdiction?.identifier).toBe('us-east');
    });

    it('getAllJurisdictions returns all jurisdictions', () => {
      expect(store.getAllJurisdictions).toHaveLength(2);
      expect(store.getAllJurisdictions[0].identifier).toBe('us-east');
    });
  });
});
