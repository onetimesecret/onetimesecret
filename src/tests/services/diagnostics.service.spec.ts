// src/tests/services/diagnostics.service.spec.ts

/**
 * Tests for diagnostics.service.ts (Sentry integration layer)
 *
 * Issue: #2790 - PR review fixes
 * Issue: #2964 - Sentry setTag vs setExtras separation
 *
 * Covers initialization, captureException, captureMessage, console
 * fallback when Sentry is unavailable, context isolation between
 * successive captures (validates the Scope.clone() fix from Issue 4),
 * and tag/extras separation for Sentry indexing.
 *
 * Run:
 *   pnpm test src/tests/services/diagnostics.service.spec.ts
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ---------------------------------------------------------------------------
// Mock Scope class that tracks method calls and supports clone()
// ---------------------------------------------------------------------------
function createMockScope() {
  const scope: Record<string, ReturnType<typeof vi.fn>> & {
    _extras: Record<string, unknown>;
    _tags: Record<string, string>;
  } = {
    _extras: {},
    _tags: {},
    setExtras: vi.fn(function (this: typeof scope, extras: Record<string, unknown>) {
      Object.assign(this._extras, extras);
      return this;
    }),
    setTag: vi.fn(function (this: typeof scope, key: string, value: string) {
      this._tags[key] = value;
      return this;
    }),
    clone: vi.fn(function (this: typeof scope) {
      const cloned = createMockScope();
      // Simulate copying existing extras and tags from the base scope
      cloned._extras = { ...this._extras };
      cloned._tags = { ...this._tags };
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
      // Use non-tag fields to test basic functionality
      const context = { count: 42, detail: 'info' };

      captureException(error, context);

      // Should clone the base scope
      expect(baseScope.clone).toHaveBeenCalledOnce();

      // The cloned scope should receive the extras (non-tag fields)
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

      // Use non-tag fields to test basic functionality
      const context = { source: 'test', detail: 'info' };
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

  // ========================================================================
  // Tag extraction (Issue #2964: Sentry setTag vs setExtras separation)
  // ========================================================================
  describe('tag extraction', () => {
    // Tag fields: componentName, errorType, errorSeverity, schema, service,
    //             jurisdiction, planid, role
    // These should be extracted and set via setTag() with lowercase values

    describe('captureException', () => {
      it('extracts componentName as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { componentName: 'SecretForm' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('componentName', 'secretform');
      });

      it('extracts errorSeverity as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { errorSeverity: 'ERROR' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorSeverity', 'error');
      });

      it('extracts errorType as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { errorType: 'TECHNICAL' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorType', 'technical');
      });

      it('extracts schema as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { schema: 'SecretResponse' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'secretresponse');
      });

      it('extracts service as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { service: 'WEB' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('service', 'web');
      });

      it('extracts jurisdiction as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { jurisdiction: 'EU' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('jurisdiction', 'eu');
      });

      it('extracts planid as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { planid: 'ENTERPRISE_V2' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('planid', 'enterprise_v2');
      });

      it('extracts role as tag with lowercase value', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), { role: 'CUSTOMER' });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('role', 'customer');
      });

      it('extracts all 8 tag fields when present', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          componentName: 'SecretForm',
          errorType: 'HUMAN',
          errorSeverity: 'ERROR',
          schema: 'UserResponse',
          service: 'API',
          jurisdiction: 'US',
          planid: 'PRO',
          role: 'COLONEL',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('componentName', 'secretform');
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorType', 'human');
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorSeverity', 'error');
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'userresponse');
        expect(clonedScope.setTag).toHaveBeenCalledWith('service', 'api');
        expect(clonedScope.setTag).toHaveBeenCalledWith('jurisdiction', 'us');
        expect(clonedScope.setTag).toHaveBeenCalledWith('planid', 'pro');
        expect(clonedScope.setTag).toHaveBeenCalledWith('role', 'colonel');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(8);
      });

      it('separates tag fields from non-tag fields correctly', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          errorType: 'SECURITY',
          schema: 'SecretResponse',
          issues: [{ path: 'field', message: 'invalid' }],
          userId: '12345',
          timestamp: Date.now(),
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        // Tag fields should be set via setTag
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorType', 'security');
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'secretresponse');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(2);

        // Non-tag fields should be set via setExtras
        expect(clonedScope.setExtras).toHaveBeenCalledTimes(1);
        const extrasArg = clonedScope.setExtras.mock.calls[0][0];
        expect(extrasArg).toHaveProperty('issues');
        expect(extrasArg).toHaveProperty('userId', '12345');
        expect(extrasArg).toHaveProperty('timestamp');
        expect(extrasArg).not.toHaveProperty('errorType');
        expect(extrasArg).not.toHaveProperty('schema');
      });

      it('does not call setTag for null tag values', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          errorType: null,
          schema: 'SecretResponse',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        // Only schema should be set as a tag
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'secretresponse');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(1);

        // Tag fields with null values are skipped, not moved to extras
        // Since there are no non-tag fields, setExtras should not be called
        expect(clonedScope.setExtras).not.toHaveBeenCalled();
      });

      it('does not call setTag for undefined tag values', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          errorType: undefined,
          schema: 'SecretResponse',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        // Only schema should be set as a tag
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'secretresponse');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(1);

        // Tag fields with undefined values are skipped, not moved to extras
        // Since there are no non-tag fields, setExtras should not be called
        expect(clonedScope.setExtras).not.toHaveBeenCalled();
      });

      it('sets empty string tag values (does not skip them)', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          errorType: '',
          schema: 'SecretResponse',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        // Empty string is a valid value, should be set as tag
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorType', '');
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'secretresponse');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(2);
      });

      it('context with only non-tag fields calls setExtras only', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          userId: '12345',
          action: 'create',
          payload: { data: 'test' },
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        expect(clonedScope.setTag).not.toHaveBeenCalled();
        expect(clonedScope.setExtras).toHaveBeenCalledWith({
          userId: '12345',
          action: 'create',
          payload: { data: 'test' },
        });
      });

      it('context with only tag fields does not call setExtras', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureException(new Error('test'), {
          componentName: 'SecretForm',
          errorType: 'technical',
          errorSeverity: 'warning',
          schema: 'SecretResponse',
          service: 'web',
          jurisdiction: 'eu',
          planid: 'basic',
          role: 'customer',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        expect(clonedScope.setTag).toHaveBeenCalledTimes(8);
        expect(clonedScope.setExtras).not.toHaveBeenCalled();
      });

      it('converts non-string tag values to strings', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        // Pass a number (which will be stringified)
        captureException(new Error('test'), {
          errorType: 123 as unknown as string,
        });

        const clonedScope = baseScope.clone.mock.results[0].value;
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorType', '123');
      });
    });

    describe('captureMessage', () => {
      it('extracts tag fields the same way as captureException', async () => {
        const { initDiagnostics, captureMessage } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureMessage('test message', {
          componentName: 'SecretForm',
          errorType: 'HUMAN',
          errorSeverity: 'ERROR',
          schema: 'UserResponse',
          service: 'API',
          jurisdiction: 'US',
          planid: 'PRO',
          role: 'COLONEL',
          customField: 'value',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        // All 8 tag fields should be extracted
        expect(clonedScope.setTag).toHaveBeenCalledWith('componentName', 'secretform');
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorType', 'human');
        expect(clonedScope.setTag).toHaveBeenCalledWith('errorSeverity', 'error');
        expect(clonedScope.setTag).toHaveBeenCalledWith('schema', 'userresponse');
        expect(clonedScope.setTag).toHaveBeenCalledWith('service', 'api');
        expect(clonedScope.setTag).toHaveBeenCalledWith('jurisdiction', 'us');
        expect(clonedScope.setTag).toHaveBeenCalledWith('planid', 'pro');
        expect(clonedScope.setTag).toHaveBeenCalledWith('role', 'colonel');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(8);

        // Non-tag field should go to extras
        expect(clonedScope.setExtras).toHaveBeenCalledWith({ customField: 'value' });
      });

      it('handles null/undefined tag values correctly', async () => {
        const { initDiagnostics, captureMessage } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        captureMessage('test message', {
          errorType: null,
          schema: undefined,
          service: 'web',
        });

        const clonedScope = baseScope.clone.mock.results[0].value;

        // Only service should be set as a tag
        expect(clonedScope.setTag).toHaveBeenCalledWith('service', 'web');
        expect(clonedScope.setTag).toHaveBeenCalledTimes(1);

        // Tag fields with null/undefined values are skipped, not moved to extras
        // Since there are no non-tag fields, setExtras should not be called
        expect(clonedScope.setExtras).not.toHaveBeenCalled();
      });
    });

    describe('tag isolation between calls', () => {
      it('tags from one call do not leak to the next', async () => {
        const { initDiagnostics, captureException } = await importFresh();
        const client = createMockClient();
        const baseScope = createMockScope();

        initDiagnostics(client as never, baseScope as never);

        // First call with tags
        captureException(new Error('first'), {
          errorType: 'security',
          schema: 'SecretResponse',
        });

        // Second call without tags
        captureException(new Error('second'), {
          customField: 'value',
        });

        const secondClonedScope = baseScope.clone.mock.results[1].value;

        // Second call should not have any tags set
        expect(secondClonedScope.setTag).not.toHaveBeenCalled();

        // Base scope should never have setTag called directly
        expect(baseScope.setTag).not.toHaveBeenCalled();
      });
    });
  });
});
