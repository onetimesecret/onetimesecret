// tests/unit/vue/stores/jurisdictionStore.spec.ts

import { ApiError } from '@/schemas';
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
      store.init(mockRegionConfig);

      expect(store.enabled).toBe(true);
      expect(store.jurisdictions).toHaveLength(2);
      expect(store.currentJurisdiction).toEqual(mockJurisdictions[0]);
    });

    it('handles disabled config', () => {
      const disabledConfig: RegionsConfig = {
        ...mockRegionConfig,
        enabled: false,
      };

      store.init(disabledConfig);

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

      store.init(singleJurisdictionConfig);

      expect(store.jurisdictions).toHaveLength(1);
      expect(store.currentJurisdiction).toEqual(mockJurisdictions[0]);
    });
  });

  describe('findJurisdiction', () => {
    beforeEach(() => {
      store.init(mockRegionConfig);
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
  });

  describe('error handling', () => {
    beforeEach(() => {
      store.init(mockRegionConfig);
    });

    it('handles null config gracefully', () => {
      expect(() => {
        store.init(null as any);
      }).not.toThrow();

      expect(store.enabled).toBe(false);
    });

    it('handles malformed jurisdiction data', () => {
      const malformedConfig = {
        ...mockRegionConfig,
        jurisdictions: [{ identifier: 'broken' }], // Missing required fields
      };

      expect(() => {
        store.init(malformedConfig as any);
      }).toThrow();
    });

    it('handles missing current_jurisdiction', () => {
      const invalidConfig = {
        ...mockRegionConfig,
        current_jurisdiction: undefined,
      };

      expect(() => {
        store.init(invalidConfig as any);
      }).toThrow();
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
        store.init(emptyConfig);
      }).toThrow(); //

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

      store.init(configWithDisabled);
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
        store.init(invalidConfig);
      }).toThrow();
    });
  });

  describe('getters', () => {
    beforeEach(() => {
      store.init(mockRegionConfig);
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
