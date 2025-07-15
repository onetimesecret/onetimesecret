// src/services/window-service-integration.spec.ts

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { WindowService } from '@/services/window.service';
import { setupWindowState, setupEmptyWindowState } from '@/tests/setup/setupWindow';
import { stateFixture } from '@/tests/fixtures/window.fixture';
import type { OnetimeWindow } from '@/types/declarations/window';

describe('WindowService Integration Tests', () => {
  let originalWindow: typeof window;

  beforeEach(() => {
    originalWindow = window;
    setupWindowState();
  });

  afterEach(() => {
    window = originalWindow;
  });

  describe('getState()', () => {
    it('returns the complete window state', () => {
      const state = WindowService.getState();

      expect(state).toBeDefined();
      expect(typeof state).toBe('object');
      expect(state).toHaveProperty('authenticated');
      expect(state).toHaveProperty('ot_version');
      expect(state).toHaveProperty('locale');
    });

    it('throws error when window is undefined', () => {
      // Mock window as undefined (SSR scenario)
      Object.defineProperty(global, 'window', {
        value: undefined,
        writable: true
      });

      expect(() => WindowService.getState()).toThrow('[WindowService] Window is not defined');
    });

    it('throws error when window.onetime is not set', () => {
      // Remove the onetime property
      delete (window as any).onetime;

      expect(() => WindowService.getState()).toThrow('[WindowService] State is not set');
    });
  });

  describe('get()', () => {
    beforeEach(() => {
      setupWindowState(stateFixture);
    });

    describe('core user data access', () => {
      it('retrieves authenticated status', () => {
        const authenticated = WindowService.get('authenticated');
        expect(typeof authenticated).toBe('boolean');
        expect(authenticated).toBe(false);
      });

      it('retrieves customer ID', () => {
        const custid = WindowService.get('custid');
        expect(custid).toBe('');
      });

      it('retrieves customer object', () => {
        const cust = WindowService.get('cust');
        expect(cust).toBeNull();
      });

      it('retrieves email', () => {
        const email = WindowService.get('email');
        expect(email).toBe('test@example.com');
      });
    });

    describe('configuration section access', () => {
      it('retrieves authentication settings', () => {
        const auth = WindowService.get('authentication');
        expect(auth).toBeDefined();
        expect(auth).toHaveProperty('enabled');
        expect(auth).toHaveProperty('signin');
        expect(auth).toHaveProperty('signup');
        expect(auth).toHaveProperty('autoverify');
        expect(typeof auth.enabled).toBe('boolean');
      });

      it('retrieves secret options', () => {
        const secretOptions = WindowService.get('secret_options');
        expect(secretOptions).toBeDefined();
        expect(secretOptions).toHaveProperty('default_ttl');
        expect(secretOptions).toHaveProperty('ttl_options');
        expect(typeof secretOptions.default_ttl).toBe('number');
        expect(Array.isArray(secretOptions.ttl_options)).toBe(true);
      });

      it('retrieves regions configuration', () => {
        const regions = WindowService.get('regions');
        expect(regions).toBeDefined();
        expect(regions).toHaveProperty('enabled');
        expect(regions).toHaveProperty('current_jurisdiction');
        expect(typeof regions.enabled).toBe('boolean');
      });

      it('retrieves ui configuration', () => {
        const ui = WindowService.get('ui');
        expect(ui).toBeDefined();
        expect(ui).toHaveProperty('enabled');
        expect(typeof ui.enabled).toBe('boolean');
      });
    });

    describe('system information access', () => {
      it('retrieves version information', () => {
        const version = WindowService.get('ot_version');
        const versionLong = WindowService.get('ot_version_long');
        const rubyVersion = WindowService.get('ruby_version');

        expect(typeof version).toBe('string');
        expect(typeof versionLong).toBe('string');
        expect(typeof rubyVersion).toBe('string');
        expect(version).toBeTruthy();
      });

      it('retrieves security tokens', () => {
        const shrimp = WindowService.get('shrimp');
        expect(typeof shrimp).toBe('string');
        expect(shrimp).toBeTruthy();
      });

      it('retrieves host information', () => {
        const siteHost = WindowService.get('site_host');
        const frontendHost = WindowService.get('frontend_host');

        expect(typeof siteHost).toBe('string');
        expect(typeof frontendHost).toBe('string');
      });
    });

    describe('feature flag access', () => {
      it('retrieves boolean feature flags', () => {
        const flags = [
          'domains_enabled',
          'regions_enabled',
          'plans_enabled',
          'i18n_enabled',
          'd9s_enabled'
        ] as const;

        flags.forEach(flag => {
          const value = WindowService.get(flag);
          expect(typeof value).toBe('boolean');
        });
      });
    });

    describe('internationalization access', () => {
      it('retrieves locale information', () => {
        const locale = WindowService.get('locale');
        const defaultLocale = WindowService.get('default_locale');
        const supportedLocales = WindowService.get('supported_locales');
        const fallbackLocale = WindowService.get('fallback_locale');

        expect(typeof locale).toBe('string');
        expect(typeof defaultLocale).toBe('string');
        expect(Array.isArray(supportedLocales)).toBe(true);
        expect(typeof fallbackLocale).toBe('string');
      });
    });

    describe('business logic access', () => {
      it('retrieves plan information', () => {
        const defaultPlanid = WindowService.get('default_planid');
        const availablePlans = WindowService.get('available_plans');
        const isPaid = WindowService.get('is_paid');

        expect(typeof defaultPlanid).toBe('string');
        expect(typeof availablePlans).toBe('object');
        expect(typeof isPaid).toBe('boolean');
      });
    });

    describe('domain and branding access', () => {
      it('retrieves domain information', () => {
        const canonicalDomain = WindowService.get('canonical_domain');
        const displayDomain = WindowService.get('display_domain');
        const domainStrategy = WindowService.get('domain_strategy');

        expect(typeof canonicalDomain).toBe('string');
        expect(typeof displayDomain).toBe('string');
        expect(['canonical', 'subdomain', 'custom', 'invalid']).toContain(domainStrategy);
      });

      it('retrieves branding information', () => {
        const domainBranding = WindowService.get('domain_branding');
        const domainLogo = WindowService.get('domain_logo');

        expect(typeof domainBranding).toBe('object');
        expect(typeof domainLogo).toBe('object');
      });
    });
  });

  describe('getMultiple()', () => {
    beforeEach(() => {
      setupWindowState(stateFixture);
    });

    describe('array input pattern', () => {
      it('retrieves multiple properties by array', () => {
        const props = WindowService.getMultiple([
          'authenticated',
          'ot_version',
          'locale'
        ]);

        expect(props).toHaveProperty('authenticated');
        expect(props).toHaveProperty('ot_version');
        expect(props).toHaveProperty('locale');
        expect(typeof props.authenticated).toBe('boolean');
        expect(typeof props.ot_version).toBe('string');
        expect(typeof props.locale).toBe('string');
      });

      it('handles empty array input', () => {
        const props = WindowService.getMultiple([]);
        expect(Object.keys(props)).toHaveLength(0);
      });

      it('maintains type safety with array input', () => {
        const props = WindowService.getMultiple(['regions_enabled', 'regions']);

        // TypeScript should infer these types correctly
        expect(typeof props.regions_enabled).toBe('boolean');
        expect(typeof props.regions).toBe('object');
      });
    });

    describe('object input pattern with defaults', () => {
      it('retrieves properties with default values', () => {
        // Test with a missing/undefined property
        setupEmptyWindowState();

        const props = WindowService.getMultiple({
          authenticated: false,
          ot_version: 'unknown',
          locale: 'en'
        });

        expect(props.authenticated).toBe(false);
        expect(props.ot_version).toBe('unknown');
        expect(props.locale).toBe('en');
      });

      it('uses actual values when available, ignores defaults', () => {
        const props = WindowService.getMultiple({
          authenticated: true, // default true, but actual is false
          locale: 'fr' // default fr, but actual is 'en'
        });

        expect(props.authenticated).toBe(false); // actual value
        expect(props.locale).toBe('en'); // actual value
      });

      it('applies defaults for null/undefined values', () => {
        // Set up state with some null values
        setupWindowState({
          ...stateFixture,
          custid: null as any,
          customer_since: undefined as any
        });

        const props = WindowService.getMultiple({
          custid: 'default-customer-id',
          customer_since: '2024-01-01'
        });

        expect(props.custid).toBe('default-customer-id');
        expect(props.customer_since).toBe('2024-01-01');
      });
    });

    describe('comprehensive property retrieval', () => {
      it('can retrieve all major sections in one call', () => {
        const props = WindowService.getMultiple([
          'authenticated',
          'authentication',
          'secret_options',
          'regions',
          'ui',
          'diagnostics',
          'ot_version',
          'locale',
          'domains_enabled',
          'is_paid'
        ]);

        // Verify all sections are present with correct types
        expect(typeof props.authenticated).toBe('boolean');
        expect(typeof props.authentication).toBe('object');
        expect(typeof props.secret_options).toBe('object');
        expect(typeof props.regions).toBe('object');
        expect(typeof props.ui).toBe('object');
        expect(typeof props.diagnostics).toBe('object');
        expect(typeof props.ot_version).toBe('string');
        expect(typeof props.locale).toBe('string');
        expect(typeof props.domains_enabled).toBe('boolean');
        expect(typeof props.is_paid).toBe('boolean');
      });
    });
  });

  describe('error handling and edge cases', () => {
    it.skip('handles window state corruption gracefully', () => {
      // Corrupt the window state
      (window as any).onetime = 'invalid-data';

      expect(() => WindowService.getState()).toThrow();
    });

    it('maintains type safety even with invalid data', () => {
      // Set up state with some invalid types
      setupWindowState({
        ...stateFixture,
        authenticated: 'not-a-boolean' as any,
        ot_version: null as any
      });

      // WindowService should still return the data, type checking is at compile time
      const authenticated = WindowService.get('authenticated');
      const version = WindowService.get('ot_version');

      expect(authenticated).toBe('not-a-boolean');
      expect(version).toBeNull();
    });

    it('handles missing nested properties', () => {
      setupWindowState({
        ...stateFixture,
        authentication: {} as any // missing required fields
      });

      const auth = WindowService.get('authentication');
      expect(auth).toEqual({});
    });
  });

  describe('performance considerations', () => {
    it('calls getState() for each get() call without caching', () => {
      const spy = vi.spyOn(WindowService, 'getState');

      // Multiple calls should call getState() once per get() call
      WindowService.get('authenticated');
      WindowService.get('ot_version');

      // getState is called once per get() call, not cached between calls
      expect(spy).toHaveBeenCalledTimes(2);

      spy.mockRestore();
    });

    it('handles large getMultiple() calls efficiently', () => {
      const allKeys = Object.keys(stateFixture) as (keyof OnetimeWindow)[];

      const startTime = performance.now();
      const props = WindowService.getMultiple(allKeys);
      const endTime = performance.now();

      expect(Object.keys(props)).toHaveLength(allKeys.length);
      expect(endTime - startTime).toBeLessThan(50); // Should be fast
    });
  });
});
