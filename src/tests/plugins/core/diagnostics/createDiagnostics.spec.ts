// src/tests/plugins/core/createDiagnostics.spec.ts
//
// Integration tests for the createDiagnostics plugin function.
// Tests jurisdiction tagging and Sentry client initialization.
//
// Issue: #2970 - Add jurisdiction tag to Sentry events

/* eslint-disable max-classes-per-file */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Router } from 'vue-router';

// ---------------------------------------------------------------------------
// Mocks - must use vi.hoisted() for variables used in vi.mock factories
// ---------------------------------------------------------------------------
const {
  mockSetTag,
  mockSetUser,
  mockSetClient,
  mockClientInit,
  mockClientClose,
  mockInitDiagnostics,
  mockSetTransactionName,
  mockSetCurrentClient,
  mockCurrentScopeSetTag,
  mockCurrentScopeSetUser,
  mockGetCurrentScope,
  mockGetBootstrapValue,
  MockBrowserClient,
  MockScope,
} = vi.hoisted(() => {
  const mockSetTag = vi.fn();
  // The user-context boundary writes setUser on the isolated scope.
  const mockSetUser = vi.fn();
  const mockSetClient = vi.fn();
  const mockClientInit = vi.fn();
  const mockClientClose = vi.fn().mockResolvedValue(undefined);
  const mockInitDiagnostics = vi.fn();
  const mockSetTransactionName = vi.fn();
  const mockSetCurrentClient = vi.fn();
  const mockCurrentScopeSetTag = vi.fn();
  const mockCurrentScopeSetUser = vi.fn();
  const mockGetCurrentScope = vi.fn(() => ({
    setTag: mockCurrentScopeSetTag,
    setUser: mockCurrentScopeSetUser,
  }));
  const mockGetBootstrapValue = vi.fn();

  class MockBrowserClient {
    init = mockClientInit;
    close = mockClientClose;
  }

  class MockScope {
    setClient = mockSetClient;
    setTag = mockSetTag;
    setUser = mockSetUser;
    setTransactionName = mockSetTransactionName;
  }

  return {
    mockSetTag,
    mockSetUser,
    mockSetClient,
    mockClientInit,
    mockClientClose,
    mockInitDiagnostics,
    mockSetTransactionName,
    mockSetCurrentClient,
    mockCurrentScopeSetTag,
    mockCurrentScopeSetUser,
    mockGetCurrentScope,
    mockGetBootstrapValue,
    MockBrowserClient,
    MockScope,
  };
});

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapValue: mockGetBootstrapValue,
}));

vi.mock('@sentry/browser', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@sentry/browser')>();
  return {
    ...actual,
    BrowserClient: MockBrowserClient,
    Scope: MockScope,
    setCurrentClient: mockSetCurrentClient,
    getCurrentScope: mockGetCurrentScope,
  };
});

vi.mock('@sentry/vue', () => ({
  browserTracingIntegration: vi.fn().mockReturnValue({ name: 'BrowserTracing' }),
}));

vi.mock('@/services/diagnostics.service', () => ({
  initDiagnostics: mockInitDiagnostics,
}));

// ---------------------------------------------------------------------------
// Import production code after mocks are set up
// ---------------------------------------------------------------------------

import { createDiagnostics } from '@/plugins/core/enableDiagnostics';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

function createMockRouter(): Router {
  return {
    currentRoute: {
      value: {
        params: {},
        meta: {},
      },
    },
    // afterEach returns an unregister fn in vue-router; the mock must mirror
    // that so the plugin's captured `unregisterAfterEach` is callable on unmount.
    afterEach: vi.fn(() => vi.fn()),
  } as unknown as Router;
}

const baseConfig = {
  sentry: {
    dsn: 'https://key@sentry.io/123',
    environment: 'test',
    release: '1.0.0',
  },
};

/** Test fixture host - uses 'localhost' to avoid CodeQL regex anchor false positives */
const TEST_HOST = 'example.com';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('createDiagnostics jurisdiction tagging', () => {
  const originalConsoleDebug = console.debug;

  beforeEach(() => {
    vi.clearAllMocks();
    console.debug = vi.fn();
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  it('sets jurisdiction tag when regions.current_jurisdiction is "EU"', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'EU' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'eu');
  });

  it('sets jurisdiction tag when regions.current_jurisdiction is "us"', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'us' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'us');
  });

  it('sets jurisdiction tag with mixed case "Us" normalized to lowercase', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'Us' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'us');
  });

  it('does not set jurisdiction tag when current_jurisdiction is empty string', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: '' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    // 2 setTag calls: service and site_host. The actor boundary sets NO tags.
    // The shared getBootstrapValue mock returns the same regions-shaped object
    // for every key, so the `diagnostics_ref` read yields a block the strict
    // contract rejects — the user context fails closed and clears rather than
    // partially applying. See src/plugins/core/diagnostics/actorContext.ts.
    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockSetUser).toHaveBeenCalledWith(null);
  });

  it('does not set jurisdiction tag when current_jurisdiction is null', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: null });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    // 2 setTag calls: service and site_host. The actor boundary sets NO tags.
    // The shared getBootstrapValue mock returns the same regions-shaped object
    // for every key, so the `diagnostics_ref` read yields a block the strict
    // contract rejects — the user context fails closed and clears rather than
    // partially applying. See src/plugins/core/diagnostics/actorContext.ts.
    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockSetUser).toHaveBeenCalledWith(null);
  });

  it('does not set jurisdiction tag when current_jurisdiction is undefined', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: undefined });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    // 2 setTag calls: service and site_host. The actor boundary sets NO tags.
    // The shared getBootstrapValue mock returns the same regions-shaped object
    // for every key, so the `diagnostics_ref` read yields a block the strict
    // contract rejects — the user context fails closed and clears rather than
    // partially applying. See src/plugins/core/diagnostics/actorContext.ts.
    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockSetUser).toHaveBeenCalledWith(null);
  });

  it('does not set jurisdiction tag when regions object is missing', () => {
    mockGetBootstrapValue.mockReturnValue(null);

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    // 2 setTag calls: service and site_host. The actor boundary sets NO tags.
    // The shared getBootstrapValue mock returns the same regions-shaped object
    // for every key, so the `diagnostics_ref` read yields a block the strict
    // contract rejects — the user context fails closed and clears rather than
    // partially applying. See src/plugins/core/diagnostics/actorContext.ts.
    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockSetUser).toHaveBeenCalledWith(null);
  });

  it('does not set jurisdiction tag when regions object has no current_jurisdiction property', () => {
    mockGetBootstrapValue.mockReturnValue({ other_property: 'value' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    // 2 setTag calls: service and site_host. The actor boundary sets NO tags.
    // The shared getBootstrapValue mock returns the same regions-shaped object
    // for every key, so the `diagnostics_ref` read yields a block the strict
    // contract rejects — the user context fails closed and clears rather than
    // partially applying. See src/plugins/core/diagnostics/actorContext.ts.
    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockSetUser).toHaveBeenCalledWith(null);
  });

  it('initializes Sentry client and scope', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetClient).toHaveBeenCalled();
    expect(mockClientInit).toHaveBeenCalled();
  });

  // B1/B2 — binds the client to the current scope so browserApiErrors and
  // browserTracing integrations resolve a real client (async errors captured,
  // transactions produced). See enableDiagnostics.ts setCurrentClient note.
  it('binds the client to the current scope via setCurrentClient', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetCurrentClient).toHaveBeenCalledTimes(1);
    // Same client instance that scope.setClient received.
    expect(mockSetCurrentClient.mock.calls[0][0]).toBe(mockSetClient.mock.calls[0][0]);
  });

  // #3794 C5 — setCurrentClient routes integration-captured events (unhandled
  // rejections, browserApiErrors callbacks, browserTracing transactions)
  // through the CURRENT scope. Deployment tags set only on the detached
  // isolated scope never reach those events, so they must be mirrored onto
  // the current scope too.
  it('sets deployment tags on the current scope for integration-captured events', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'EU' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockCurrentScopeSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockCurrentScopeSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockCurrentScopeSetTag).toHaveBeenCalledWith('jurisdiction', 'eu');
    // The isolated scope keeps its tags too (manual captures).
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'eu');
  });

  it('names transactions from the matched route record path on navigation', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });
    const router = createMockRouter();

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router,
    });

    // Capture the afterEach hook and simulate a navigation to a secret link
    const afterEachMock = router.afterEach as ReturnType<typeof vi.fn>;
    expect(afterEachMock).toHaveBeenCalledTimes(1);
    const hook = afterEachMock.mock.calls[0][0];

    hook({
      path: '/secret/abc123def456',
      matched: [{ path: '/secret/:secretKey' }],
    });

    // Parameterized route path, not the resolved URL with the identifier
    expect(mockSetTransactionName).toHaveBeenCalledWith('/secret/:secretKey');
  });

  it('falls back to the resolved path when no route record matched', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });
    const router = createMockRouter();

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router,
    });

    const afterEachMock = router.afterEach as ReturnType<typeof vi.fn>;
    const hook = afterEachMock.mock.calls[0][0];

    hook({ path: '/unknown-page', matched: [] });

    expect(mockSetTransactionName).toHaveBeenCalledWith('/unknown-page');
  });

  // Regression: the router.afterEach unregister fn must be captured and called
  // in the patched app.unmount so repeated mount/unmount (tests,
  // micro-frontends) don't accumulate handlers. Also verifies the original
  // client shutdown (client.close) still runs.
  it('unbinds the router.afterEach hook and closes the client on unmount', async () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });
    const router = createMockRouter();

    const plugin = createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router,
    });

    // The unregister stub returned by the mocked afterEach.
    const afterEachMock = router.afterEach as ReturnType<typeof vi.fn>;
    const unregisterAfterEach = afterEachMock.mock.results[0].value as ReturnType<typeof vi.fn>;

    // Minimal Vue App: install patches app.unmount around this original.
    const originalUnmount = vi.fn();
    const app = {
      provide: vi.fn(),
      unmount: originalUnmount,
    } as unknown as import('vue').App;

    plugin.install(app);

    expect(unregisterAfterEach).not.toHaveBeenCalled();

    // Drive the patched unmount.
    app.unmount();

    expect(unregisterAfterEach).toHaveBeenCalledTimes(1);
    expect(mockClientClose).toHaveBeenCalledWith(2000);

    // client.close resolves; the original unmount runs in the .then callback.
    await Promise.resolve();
    expect(originalUnmount).toHaveBeenCalledTimes(1);
  });
});

// ───────────────────────────────────────────────────────────────────────────────
// USER-CONTEXT WIRING
//
// The unit-level behaviour lives in actorContext.spec.ts. These cover the
// WIRING: that createDiagnostics reads the block from the pre-Pinia bootstrap
// snapshot and applies it to both scopes at the right point in boot order.
// ───────────────────────────────────────────────────────────────────────────────

describe('createDiagnostics user context', () => {
  const originalConsoleDebug = console.debug;

  /**
   * Key-aware bootstrap mock. The jurisdiction suite above uses a single
   * mockReturnValue for every key; user-context wiring needs `regions` and
   * `diagnostics_ref` to differ.
   */
  function mockBootstrap(values: Record<string, unknown>) {
    mockGetBootstrapValue.mockImplementation((key: string) => values[key]);
  }

  beforeEach(() => {
    vi.clearAllMocks();
    console.debug = vi.fn();
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  it('applies the server-provided ref to BOTH scopes', () => {
    mockBootstrap({
      regions: null,
      // 16 lowercase hex — the shape DiagnosticsRef derives and the contract
      // enforces by content.
      diagnostics_ref: { actor_ref: 'a1b2c3d4e5f60718' },
    });

    createDiagnostics({ host: TEST_HOST, config: baseConfig, router: createMockRouter() });

    const expectedUser = { id: 'a1b2c3d4e5f60718', ip_address: null };
    expect(mockSetUser).toHaveBeenCalledWith(expectedUser);
    expect(mockCurrentScopeSetUser).toHaveBeenCalledWith(expectedUser);
  });

  // The ref carries NO second dimension. Deployment tags are the only tags
  // createDiagnostics writes; identifying a session must not add one.
  it('writes no tag alongside the user context', () => {
    mockBootstrap({
      regions: null,
      diagnostics_ref: { actor_ref: '00112233445566ff' },
    });

    createDiagnostics({ host: TEST_HOST, config: baseConfig, router: createMockRouter() });

    expect(mockSetUser).toHaveBeenCalledWith({ id: '00112233445566ff', ip_address: null });
    // service + site_host only — no jurisdiction (regions null), no actor tag.
    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag.mock.calls.map((call) => call[0])).toEqual(['service', 'site_host']);
  });

  it('leaves an anonymous session unidentified — no fallback id', () => {
    // The block is ABSENT for anonymous sessions; absence is the signal.
    mockBootstrap({ regions: null, diagnostics_ref: undefined });

    createDiagnostics({ host: TEST_HOST, config: baseConfig, router: createMockRouter() });

    expect(mockSetUser).toHaveBeenCalledTimes(1);
    expect(mockSetUser).toHaveBeenCalledWith(null);
    expect(mockCurrentScopeSetUser).toHaveBeenCalledWith(null);
  });

  it('fails closed when the block carries an unexpected field', () => {
    mockBootstrap({
      regions: null,
      diagnostics_ref: {
        actor_ref: 'a1b2c3d4e5f60718',
        email: 'user@example.com',
      },
    });

    createDiagnostics({ host: TEST_HOST, config: baseConfig, router: createMockRouter() });

    expect(mockSetUser).toHaveBeenCalledWith(null);
    expect(mockSetUser).not.toHaveBeenCalledWith(
      expect.objectContaining({ id: 'a1b2c3d4e5f60718' })
    );
  });

  // Wire-contract narrowing at the boot seam: `actor_scope` was a real field on
  // this block. A server that still emits it is an older build, and the strict
  // contract refuses the whole block rather than stripping the stale key.
  it('fails closed on a legacy block still carrying actor_scope', () => {
    mockBootstrap({
      regions: null,
      diagnostics_ref: { actor_ref: 'a1b2c3d4e5f60718', actor_scope: 'deployment' },
    });

    createDiagnostics({ host: TEST_HOST, config: baseConfig, router: createMockRouter() });

    expect(mockSetUser).toHaveBeenCalledWith(null);
    expect(mockCurrentScopeSetUser).toHaveBeenCalledWith(null);
  });

  // The block a server bug / older build / compromised node could emit: the one
  // permitted key, a non-empty string. Shape-only validation accepts it and the
  // address becomes user.id on every event.
  it('fails closed when the ref is an email rather than an opaque value', () => {
    mockBootstrap({
      regions: null,
      diagnostics_ref: { actor_ref: 'alice@example.com' },
    });

    createDiagnostics({ host: TEST_HOST, config: baseConfig, router: createMockRouter() });

    expect(mockSetUser).toHaveBeenCalledWith(null);
    expect(mockCurrentScopeSetUser).toHaveBeenCalledWith(null);
  });
});
