import {
  AuthValidator,
  setupRouterGuards,
  validateAuthentication,
} from '@/router/guards.routes';
import { useAuthStore } from '@/stores';
import { beforeEach, describe, expect, it, test, vi } from 'vitest';
import { RouteLocationNormalized, Router } from 'vue-router';

const protectedRoute: RouteLocationNormalized = {
  meta: { requiresAuth: true },
  fullPath: '/protected',
  path: '/protected',
  name: 'Protected',
  params: {},
  query: {},
  hash: '',
  matched: [],
  redirectedFrom: undefined,
};

const publicRoute: RouteLocationNormalized = {
  ...protectedRoute,
  meta: { requiresAuth: false },
};

vi.mock('@/stores/authStore', () => ({
  useAuthStore: vi.fn(() => ({
    isAuthenticated: false,
    needsCheck: false,
    checkAuthStatus: vi.fn(),
  })),
}));

vi.mock('@/stores/languageStore', () => ({
  useLanguageStore: vi.fn(() => ({
    setCurrentLocale: vi.fn(),
  })),
}));

vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn(),
  },
}));

describe('Router Guards', () => {
  let router: Router;

  beforeEach(() => {
    router = {
      beforeEach: vi.fn(),
    } as unknown as Router;

    vi.clearAllMocks();
  });

  it('should setup router guards', () => {
    setupRouterGuards(router);
    expect(router.beforeEach).toHaveBeenCalled();
  });

  it('should redirect authenticated users from auth routes', async () => {
    setupRouterGuards(router);

    const guard = vi.mocked(router.beforeEach).mock.calls[0][0];
    const to = {
      meta: { isAuthRoute: true },
      query: {},
      path: '/auth',
      name: 'Auth',
      params: {},
      hash: '',
      fullPath: '/auth',
      matched: [],
      redirectedFrom: undefined
    };

    const authStore = { isAuthenticated: true };
    vi.mocked(useAuthStore).mockReturnValue(authStore as any);

    const result = await guard(to as any);

    expect(result).toEqual({ name: 'Dashboard' });
  });

  it('should handle root path redirect for authenticated users', async () => {
    setupRouterGuards(router);

    const guard = vi.mocked(router.beforeEach).mock.calls[0][0];
    const to = {
      path: '/',
      query: {},
      name: 'Home',
      params: {},
      hash: '',
      fullPath: '/',
      matched: [],
      redirectedFrom: undefined,
      meta: {}
    };

    const authStore = { isAuthenticated: true };
    vi.mocked(useAuthStore).mockReturnValue(authStore as any);

    const result = await guard(to as any);

    expect(result).toEqual({ name: 'Dashboard' });
  });

  describe('validateAuthentication', () => {
    let mockValidator: AuthValidator;
    let protectedRoute: RouteLocationNormalized;

    beforeEach(() => {
      // Create mock validator with vi.fn() for methods
      mockValidator = {
        needsCheck: true,
        isAuthenticated: null,
        checkAuthStatus: vi.fn().mockImplementation(async () => true),
      } satisfies AuthValidator;

      protectedRoute = {
        meta: { requiresAuth: true },
        // Add other required RouteLocationNormalized properties
      } as RouteLocationNormalized;
    });

    test('performs check when needed on protected route', async () => {
      mockValidator.needsCheck = true;
      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(mockValidator.checkAuthStatus).toHaveBeenCalled();
      expect(result).toBe(true);
    });

    test('skips check when not needed on protected route', async () => {
      // Set up authenticated state
      mockValidator.needsCheck = false;
      mockValidator.isAuthenticated = true; // Add this line to indicate authenticated state

      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(mockValidator.checkAuthStatus).not.toHaveBeenCalled();
      expect(result).toBe(true);
    });

    test('skips return false when no need for a check', async () => {
      //  when `needsCheck` is false but `isAuthenticated` is null (the default
      // value in our setup), the validator should return false for protected routes.
      mockValidator.needsCheck = false;
      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(mockValidator.checkAuthStatus).not.toHaveBeenCalled();
      expect(result).toBe(false);
    });

    test('always returns true for public routes', async () => {
      mockValidator.needsCheck = true;
      mockValidator.isAuthenticated = false;
      const result = await validateAuthentication(mockValidator, publicRoute);
      expect(mockValidator.checkAuthStatus).not.toHaveBeenCalled();
      expect(result).toBe(true);
    });

    test('returns false when auth check fails', async () => {
      mockValidator.needsCheck = true;
      mockValidator.checkAuthStatus.mockResolvedValueOnce(false);
      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(result).toBe(false);
    });

    test('returns false when authenticated is null', async () => {
      mockValidator.needsCheck = false;
      mockValidator.isAuthenticated = null;
      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(result).toBe(false);
    });
  });
});
