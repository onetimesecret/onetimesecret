// src/tests/router/secret.routes.spec.ts

import routes from '@/router/secret.routes';
import ShowSecretContainer from '@/views/secrets/ShowSecretContainer.vue';
import { describe, expect, it } from 'vitest';

describe('Secret Routes', () => {
  const secretRoute = routes.find((route) => route.path === '/secret/:secretIdentifier');

  describe('route configuration', () => {
    it('should define basic route properties correctly', () => {
      expect(secretRoute).toBeDefined();
      expect(secretRoute?.path).toBe('/secret/:secretIdentifier');
      expect(secretRoute?.name).toBe('Secret link');
      expect(secretRoute?.component).toBe(ShowSecretContainer);
    });
  });

  describe('secretIdentifier validation', () => {
    it('should allow valid secret keys', () => {
      const guard = secretRoute?.beforeEnter;
      if (!guard) throw new Error('beforeEnter guard not defined');

      const mockRoute = {
        params: { secretIdentifier: 'abc123' },
      };

      const result = guard(mockRoute as any);
      expect(result).toBeUndefined(); // guard allows navigation to proceed
    });

    it('should redirect to Not Found for invalid secret keys', () => {
      const guard = secretRoute?.beforeEnter;
      if (!guard) throw new Error('beforeEnter guard not defined');

      const invalidKeys = ['abc 123', 'abc@123', '', 'abc/123'];

      invalidKeys.forEach((key) => {
        const mockRoute = {
          params: { secretIdentifier: key },
        };

        const result = guard(mockRoute as any);
        expect(result).toEqual({ name: 'Not Found' });
      });
    });
  });

  describe('props', () => {
    it('should pass secretIdentifier as a prop', () => {
      const propsFunc = secretRoute?.props;
      if (typeof propsFunc !== 'function') throw new Error('props should be a function');

      const mockRoute = {
        params: { secretIdentifier: 'abc123' },
      };

      const props = propsFunc(mockRoute as any);
      expect(props).toEqual({ secretIdentifier: 'abc123' });
    });
  });
});
