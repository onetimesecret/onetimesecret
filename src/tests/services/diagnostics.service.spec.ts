// src/tests/services/diagnostics.service.spec.ts

/**
 * Tests for diagnostics.service.ts (Sentry integration layer)
 *
 * Issue: #2790 - PR review fixes
 *
 * Covers initialization, captureException, captureMessage, console
 * fallback when Sentry is unavailable, and context isolation between
 * successive captures (validates the Scope.clone() fix from Issue 4).
 *
 * Run:
 *   pnpm test src/tests/services/diagnostics.service.spec.ts
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ---------------------------------------------------------------------------
// Mock Scope class that tracks method calls and supports clone()
// ---------------------------------------------------------------------------
function createMockScope() {
  const scope: Record<string, ReturnType<typeof vi.fn>> & { _extras: Record<string, unknown> } = {
    _extras: {},
    setExtras: vi.fn(function (this: typeof scope, extras: Record<string, unknown>) {
      Object.assign(this._extras, extras);
      return this;
    }),
    clone: vi.fn(function (this: typeof scope) {
      const cloned = createMockScope();
      // Simulate copying existing extras from the base scope
      cloned._extras = { ...this._extras };
      return cloned;
    }),
    captureException: vi.fn(),
    captureMessage: vi.fn(),
  };
  return scope;
}

// Create a mock Scope constructor that returns a mock instance when
// instantiated via `new Scope()`, while also acting as a value import
// for the module under test.
const MockScopeClass = vi.fn().mockImplementation(() => createMockScope());

vi.mock('@sentry/browser', () => ({
  Scope: MockScopeClass,
}));

// ---------------------------------------------------------------------------
// Helper: fresh import of the diagnostics service (resets module state)
// ---------------------------------------------------------------------------
async function importFresh() {
  vi.resetModules();
  const mod = await import('@/services/diagnostics.service');
  return mod;
}

function createMockClient() {
  return {
    captureException: vi.fn(),
    captureMessage: vi.fn(),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('diagnostics.service', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.resetModules();
  });

  // ========================================================================
  // initDiagnostics / isDiagnosticsEnabled
  // ========================================================================
  describe('initDiagnostics', () => {
    it('sets the internal client so isDiagnosticsEnabled returns true', async () => {
      const { initDiagnostics, isDiagnosticsEnabled } = await importFresh();
      const client = createMockClient();
      const scope = createMockScope();

      expect(isDiagnosticsEnabled()).toBe(false);

      initDiagnostics(client as never, scope as never);

      expect(isDiagnosticsEnabled()).toBe(true);
    });
  });

  describe('isDiagnosticsEnabled', () => {
    it('returns false before initialization', async () => {
      const { isDiagnosticsEnabled } = await importFresh();
      expect(isDiagnosticsEnabled()).toBe(false);
    });

    it('returns true after initialization', async () => {
      const { initDiagnostics, isDiagnosticsEnabled } = await importFresh();
      initDiagnostics(createMockClient() as never, createMockScope() as never);
      expect(isDiagnosticsEnabled()).toBe(true);
    });
  });

  // ========================================================================
  // captureException
  // ========================================================================
  describe('captureException', () => {
    it('with Sentry initialized: clones scope and calls client.captureException', async () => {
      const { initDiagnostics, captureException } = await importFresh();
      const client = createMockClient();
      const baseScope = createMockScope();

      initDiagnostics(client as never, baseScope as never);

      const error = new Error('test error');
      const context = { schema: 'TestSchema', count: 42 };

      captureException(error, context);

      // Should clone the base scope
      expect(baseScope.clone).toHaveBeenCalledOnce();

      // The cloned scope should receive the extras
      const clonedScope = baseScope.clone.mock.results[0].value;
      expect(clonedScope.setExtras).toHaveBeenCalledWith(context);

      // Client should be called with the cloned scope, not the base scope
      expect(client.captureException).toHaveBeenCalledWith(error, undefined, clonedScope);
    });

    it('without context: captures without setting extras', async () => {
      const { initDiagnostics, captureException } = await importFresh();
      const client = createMockClient();
      const baseScope = createMockScope();

      initDiagnostics(client as never, baseScope as never);

      const error = new Error('no context error');
      captureException(error);

      expect(baseScope.clone).toHaveBeenCalledOnce();

      const clonedScope = baseScope.clone.mock.results[0].value;
      expect(clonedScope.setExtras).not.toHaveBeenCalled();
      expect(client.captureException).toHaveBeenCalledWith(error, undefined, clonedScope);
    });

    it('without Sentry: falls back to console.error', async () => {
      const { captureException } = await importFresh();
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      const error = new Error('fallback error');
      const context = { detail: 'info' };

      captureException(error, context);

      expect(consoleSpy).toHaveBeenCalledWith(
        '[Diagnostics] Exception captured (Sentry unavailable):',
        error
      );
      expect(consoleSpy).toHaveBeenCalledWith(
        '[Diagnostics] Context:',
        context
      );

      consoleSpy.mockRestore();
    });
  });

  // ========================================================================
  // captureMessage
  // ========================================================================
  describe('captureMessage', () => {
    it('with Sentry initialized: clones scope and calls client.captureMessage', async () => {
      const { initDiagnostics, captureMessage } = await importFresh();
      const client = createMockClient();
      const baseScope = createMockScope();

      initDiagnostics(client as never, baseScope as never);

      const context = { source: 'test' };
      captureMessage('test message', context);

      expect(baseScope.clone).toHaveBeenCalledOnce();

      const clonedScope = baseScope.clone.mock.results[0].value;
      expect(clonedScope.setExtras).toHaveBeenCalledWith(context);
      expect(client.captureMessage).toHaveBeenCalledWith('test message', undefined, undefined, clonedScope);
    });

    it('without context: captures without setting extras', async () => {
      const { initDiagnostics, captureMessage } = await importFresh();
      const client = createMockClient();
      const baseScope = createMockScope();

      initDiagnostics(client as never, baseScope as never);

      captureMessage('bare message');

      const clonedScope = baseScope.clone.mock.results[0].value;
      expect(clonedScope.setExtras).not.toHaveBeenCalled();
      expect(client.captureMessage).toHaveBeenCalledWith('bare message', undefined, undefined, clonedScope);
    });

    it('without Sentry: falls back to console.warn', async () => {
      const { captureMessage } = await importFresh();
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      captureMessage('fallback message', { key: 'val' });

      expect(consoleSpy).toHaveBeenCalledWith(
        '[Diagnostics] Message captured (Sentry unavailable):',
        'fallback message'
      );
      expect(consoleSpy).toHaveBeenCalledWith(
        '[Diagnostics] Context:',
        { key: 'val' }
      );

      consoleSpy.mockRestore();
    });
  });

  // ========================================================================
  // Context isolation (validates Scope.clone() fix)
  // ========================================================================
  describe('context isolation', () => {
    it('extras from one captureException call do not leak to the next', async () => {
      const { initDiagnostics, captureException } = await importFresh();
      const client = createMockClient();
      const baseScope = createMockScope();

      initDiagnostics(client as never, baseScope as never);

      // First call with context
      captureException(new Error('first'), { leaky: 'data' });

      // Second call without context
      captureException(new Error('second'));

      // Each call should clone independently
      expect(baseScope.clone).toHaveBeenCalledTimes(2);

      // The second cloned scope should NOT have setExtras called
      const secondClonedScope = baseScope.clone.mock.results[1].value;
      expect(secondClonedScope.setExtras).not.toHaveBeenCalled();

      // Verify the base scope's _extras were never mutated directly
      expect(baseScope.setExtras).not.toHaveBeenCalled();
    });

    it('extras from one captureMessage call do not leak to the next', async () => {
      const { initDiagnostics, captureMessage } = await importFresh();
      const client = createMockClient();
      const baseScope = createMockScope();

      initDiagnostics(client as never, baseScope as never);

      captureMessage('first', { leaky: 'data' });
      captureMessage('second');

      expect(baseScope.clone).toHaveBeenCalledTimes(2);

      const secondClonedScope = baseScope.clone.mock.results[1].value;
      expect(secondClonedScope.setExtras).not.toHaveBeenCalled();
      expect(baseScope.setExtras).not.toHaveBeenCalled();
    });
  });
});
