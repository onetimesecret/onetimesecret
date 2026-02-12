// src/tests/router/guards.routes.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, test, vi } from 'vitest';
import {
  NavigationGuardReturn,
  RouteLocationNormalized,
  RouteLocationRaw,
  Router,
} from 'vue-router';

import {
  AuthValidator,
  setupRouterGuards,
  validateAuthentication,
} from '@/router/guards.routes';
import { useAuthStore } from '@/shared/stores';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

/** Sync guard that blocks routes for disabled auth features. */
type FeatureGuard = (to: RouteLocationNormalized) => RouteLocationRaw | true;

/** Async guard that handles auth redirects and validation. */
type AuthGuard = (
  to: RouteLocationNormalized
) => Promise<NavigationGuardReturn>;

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

vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: vi.fn(() => ({
    isAuthenticated: false,
    needsCheck: false,
    checkWindowStatus: vi.fn(),
  })),
}));

vi.mock('@/shared/stores/languageStore', () => ({
  useLanguageStore: vi.fn(() => ({
    setCurrentLocale: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/usePageTitle', () => ({
  usePageTitle: vi.fn(() => ({
    setTitle: vi.fn(),
    useComputedTitle: vi.fn(),
    formatTitle: vi.fn(),
  })),
}));

describe('Router Guards', () => {
  let router: Router;
  let pinia: ReturnType<typeof createTestingPinia>;
  let _bootstrapStore: ReturnType<typeof useBootstrapStore>;

  beforeEach(() => {
    pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          authenticated: false,
          domain_strategy: 'canonical',
          site_host: 'onetimesecret.com',
          display_domain: 'onetimesecret.com',
          domains_enabled: false,
          cust: null,
        },
      },
    });
    setActivePinia(pinia);
    _bootstrapStore = useBootstrapStore();

    router = {
      beforeEach: vi.fn(),
      afterEach: vi.fn(),
    } as unknown as Router;

    vi.clearAllMocks();
  });

  it('should setup router guards', () => {
    setupRouterGuards(router);
    expect(router.beforeEach).toHaveBeenCalled();
  });

  it('should redirect authenticated users from auth routes', async () => {
    setupRouterGuards(router);

    // Index 1: main guard (index 0 is the feature-check guard)
    const guard = vi.mocked(router.beforeEach).mock.calls[1][0] as AuthGuard;
    const to: RouteLocationNormalized = {
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

    const authStore = { isAuthenticated: true, isFullyAuthenticated: true };
    vi.mocked(useAuthStore).mockReturnValue(authStore as ReturnType<typeof useAuthStore>);

    const result = await guard(to);

    expect(result).toEqual({ name: 'Dashboard' });
  });

  it('should handle root path redirect for authenticated users', async () => {
    setupRouterGuards(router);

    // Index 1: main guard (index 0 is the feature-check guard)
    const guard = vi.mocked(router.beforeEach).mock.calls[1][0] as AuthGuard;
    const to: RouteLocationNormalized = {
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

    const authStore = { isAuthenticated: true, isFullyAuthenticated: true };
    vi.mocked(useAuthStore).mockReturnValue(authStore as ReturnType<typeof useAuthStore>);

    const result = await guard(to);

    expect(result).toEqual({ name: 'Dashboard' });
  });

  describe('disabled auth feature guard', () => {
    it('should redirect /signup to / when signup is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: false, signin: true },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signup' as const, isAuthRoute: true },
        path: '/signup',
        name: 'Sign Up',
        query: {},
        params: {},
        hash: '',
        fullPath: '/signup',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should allow /signup when signup is enabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: true },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signup' as const, isAuthRoute: true },
        path: '/signup',
        name: 'Sign Up',
        query: {},
        params: {},
        hash: '',
        fullPath: '/signup',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toBe(true);
    });

    it('should redirect /signin to / when signin is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: false },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/signin',
        name: 'Sign In',
        query: {},
        params: {},
        hash: '',
        fullPath: '/signin',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should redirect when auth is entirely disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: false, signup: true, signin: true },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signup' as const, isAuthRoute: true },
        path: '/signup',
        name: 'Sign Up',
        query: {},
        params: {},
        hash: '',
        fullPath: '/signup',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should redirect /mfa-verify to / when signin is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: false },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/mfa-verify',
        name: 'MFA Verify',
        query: {},
        params: {},
        hash: '',
        fullPath: '/mfa-verify',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should redirect /reset-password to / when signin is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: false },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/reset-password',
        name: 'Reset Password (Rodauth)',
        query: {},
        params: {},
        hash: '',
        fullPath: '/reset-password',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should block signin sub-routes when auth is entirely disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: false, signup: true, signin: true },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/email-login',
        name: 'Email Login',
        query: {},
        params: {},
        hash: '',
        fullPath: '/email-login',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should redirect /forgot to / when signin is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: false },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/forgot',
        name: 'Forgot Password',
        query: {},
        params: {},
        hash: '',
        fullPath: '/forgot',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should allow /mfa-verify when signin is enabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: true },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/mfa-verify',
        name: 'MFA Verify',
        query: {},
        params: {},
        hash: '',
        fullPath: '/mfa-verify',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toBe(true);
    });

    it('should redirect /email-login to / when signin is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: true, signin: false },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signin' as const, isAuthRoute: true },
        path: '/email-login',
        name: 'Email Login',
        query: {},
        params: {},
        hash: '',
        fullPath: '/email-login',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should redirect /signup/:planCode to / when signup is disabled', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authentication: { enabled: true, signup: false, signin: true },
      });

      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: { requiresFeature: 'signup' as const, isAuthRoute: true },
        path: '/signup/professional',
        name: 'Sign Up with Plan',
        query: {},
        params: { planCode: 'professional' },
        hash: '',
        fullPath: '/signup/professional',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toEqual({ path: '/' });
    });

    it('should not redirect routes without requiresFeature', () => {
      setupRouterGuards(router);
      const guard = vi.mocked(router.beforeEach).mock.calls[0][0] as FeatureGuard;
      const to = {
        meta: {},
        path: '/some-page',
        name: 'Some Page',
        query: {},
        params: {},
        hash: '',
        fullPath: '/some-page',
        matched: [],
        redirectedFrom: undefined,
      };

      const result = guard(to as RouteLocationNormalized);
      expect(result).toBe(true);
    });
  });

  describe('validateAuthentication', () => {
    let mockValidator: AuthValidator;
    let protectedRoute: RouteLocationNormalized;

    beforeEach(() => {
      // Create mock validator with vi.fn() for methods
      mockValidator = {
        needsCheck: true,
        isAuthenticated: null,
        checkWindowStatus: vi.fn().mockImplementation(async () => true),
      } satisfies AuthValidator;

      protectedRoute = {
        meta: { requiresAuth: true },
        fullPath: '/protected',
        path: '/protected',
        name: 'Protected',
        params: {},
        query: {},
        hash: '',
        matched: [],
        redirectedFrom: undefined,
      } as RouteLocationNormalized;
    });

    test('performs check when needed on protected route', async () => {
      mockValidator.needsCheck = true;
      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(mockValidator.checkWindowStatus).toHaveBeenCalled();
      expect(result).toBe(true);
    });

    test('skips check when not needed on protected route', async () => {
      // Set up authenticated state
      mockValidator.needsCheck = false;
      mockValidator.isAuthenticated = true; // Add this line to indicate authenticated state

      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(mockValidator.checkWindowStatus).not.toHaveBeenCalled();
      expect(result).toBe(true);
    });

    test('skips return false when no need for a check', async () => {
      //  when `needsCheck` is false but `isAuthenticated` is null (the default
      // value in our setup), the validator should return false for protected routes.
      mockValidator.needsCheck = false;
      const result = await validateAuthentication(mockValidator, protectedRoute);
      expect(mockValidator.checkWindowStatus).not.toHaveBeenCalled();
      expect(result).toBe(false);
    });

    test('always returns true for public routes', async () => {
      mockValidator.needsCheck = true;
      mockValidator.isAuthenticated = false;
      const result = await validateAuthentication(mockValidator, publicRoute);
      expect(mockValidator.checkWindowStatus).not.toHaveBeenCalled();
      expect(result).toBe(true);
    });

    test('returns false when auth check fails', async () => {
      mockValidator.needsCheck = true;
      mockValidator.checkWindowStatus.mockResolvedValueOnce(false);
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
