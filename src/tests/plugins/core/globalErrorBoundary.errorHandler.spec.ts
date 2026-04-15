// src/tests/plugins/core/globalErrorBoundary.errorHandler.spec.ts
//
// Tests for createErrorBoundary() plugin - verifies error handler captures
// errors to Sentry with correct tag context.
//
// Issue: #2964 - Sentry setTag vs setExtras separation
// Issue: #2966 - Add component name to Sentry context
//
// Run:
//   pnpm test src/tests/plugins/core/globalErrorBoundary.errorHandler.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ---------------------------------------------------------------------------
// Mocks - must be hoisted before imports
// ---------------------------------------------------------------------------
const {
  mockCaptureException,
  mockIsDiagnosticsEnabled,
  mockClassifyError,
  mockIsOfHumanInterest,
  mockBootstrapStore,
} = vi.hoisted(() => {
  const mockCaptureException = vi.fn();
  const mockIsDiagnosticsEnabled = vi.fn();
  const mockClassifyError = vi.fn();
  const mockIsOfHumanInterest = vi.fn();
  const mockBootstrapStore = vi.fn();

  return {
    mockCaptureException,
    mockIsDiagnosticsEnabled,
    mockClassifyError,
    mockIsOfHumanInterest,
    mockBootstrapStore,
  };
});

vi.mock('@/services/diagnostics.service', () => ({
  captureException: mockCaptureException,
  isDiagnosticsEnabled: mockIsDiagnosticsEnabled,
}));

vi.mock('@/schemas/errors', () => ({
  classifyError: mockClassifyError,
  errorGuards: {
    isOfHumanInterest: mockIsOfHumanInterest,
  },
}));

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: mockBootstrapStore,
}));

vi.mock('@/services/logging.service', () => ({
  loggingService: {
    error: vi.fn(),
    debug: vi.fn(),
  },
}));

// ---------------------------------------------------------------------------
// Import after mocks
// ---------------------------------------------------------------------------
import { createErrorBoundary } from '@/plugins/core/globalErrorBoundary';
import type { App } from 'vue';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------
function createMockApp(): App {
  const config = {
    errorHandler: null as ((error: unknown, instance: unknown, info: string) => void) | null,
  };
  return {
    config,
    provide: vi.fn(),
    use: vi.fn(),
    mount: vi.fn(),
    unmount: vi.fn(),
  } as unknown as App;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('createErrorBoundary', () => {
  let mockApp: App;

  beforeEach(() => {
    vi.clearAllMocks();
    mockApp = createMockApp();

    // Default mock implementations
    mockIsDiagnosticsEnabled.mockReturnValue(true);
    mockClassifyError.mockReturnValue({
      message: 'Test error',
      type: 'technical',
      severity: 'error',
    });
    mockIsOfHumanInterest.mockReturnValue(false);
    mockBootstrapStore.mockReturnValue({
      regions: null,
      organization: null,
      cust: null,
    });
  });

  afterEach(() => {
    vi.resetAllMocks();
  });

  describe('plugin installation', () => {
    it('installs error handler on app.config', () => {
      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      expect(mockApp.config.errorHandler).toBeInstanceOf(Function);
    });
  });

  describe('error handler Sentry capture', () => {
    it('calls captureException when diagnostics is enabled', () => {
      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      const error = new Error('Test error');
      const instance = { $options: { name: 'TestComponent' } };

      mockApp.config.errorHandler?.(error, instance, 'setup function');

      expect(mockCaptureException).toHaveBeenCalledTimes(1);
      expect(mockCaptureException).toHaveBeenCalledWith(error, expect.any(Object));
    });

    it('does not call captureException when diagnostics is disabled', () => {
      mockIsDiagnosticsEnabled.mockReturnValue(false);

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      const error = new Error('Test error');
      mockApp.config.errorHandler?.(error, null, 'setup function');

      expect(mockCaptureException).not.toHaveBeenCalled();
    });

    it('normalizes non-Error throwables to Error instances', () => {
      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.('string error', null, 'setup function');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'string error' }),
        expect.any(Object)
      );
    });
  });

  describe('context tags', () => {
    it('passes componentName from getComponentName()', () => {
      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      const instance = { $options: { name: 'SecretForm' } };
      mockApp.config.errorHandler?.(new Error('test'), instance, 'mounted hook');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          componentName: 'SecretForm',
        })
      );
    });

    it('passes componentInfo from Vue error info', () => {
      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'mounted hook');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          componentInfo: 'mounted hook',
        })
      );
    });

    it('passes errorType from classified error', () => {
      mockClassifyError.mockReturnValue({
        message: 'Test',
        type: 'security',
        severity: 'error',
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          errorType: 'security',
        })
      );
    });

    it('passes errorSeverity from classified error', () => {
      mockClassifyError.mockReturnValue({
        message: 'Test',
        type: 'technical',
        severity: 'warning',
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          errorSeverity: 'warning',
        })
      );
    });

    it('passes jurisdiction from bootstrap store when available', () => {
      mockBootstrapStore.mockReturnValue({
        regions: { current_jurisdiction: 'EU' },
        organization: null,
        cust: null,
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          jurisdiction: 'EU',
        })
      );
    });

    it('omits jurisdiction when not configured', () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: null,
        cust: null,
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      const capturedContext = mockCaptureException.mock.calls[0][1];
      expect(capturedContext).not.toHaveProperty('jurisdiction');
    });

    it('passes planid from bootstrap store when available', () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: { planid: 'enterprise_v2' },
        cust: null,
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          planid: 'enterprise_v2',
        })
      );
    });

    it('omits planid when organization is not available', () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: null,
        cust: null,
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      const capturedContext = mockCaptureException.mock.calls[0][1];
      expect(capturedContext).not.toHaveProperty('planid');
    });

    it('passes role from bootstrap store when available', () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: null,
        cust: { role: 'colonel' },
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          role: 'colonel',
        })
      );
    });

    it('omits role when cust is not available', () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: null,
        cust: null,
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      const capturedContext = mockCaptureException.mock.calls[0][1];
      expect(capturedContext).not.toHaveProperty('role');
    });

    it('passes all available context tags together', () => {
      mockBootstrapStore.mockReturnValue({
        regions: { current_jurisdiction: 'us' },
        organization: { planid: 'pro' },
        cust: { role: 'customer' },
      });
      mockClassifyError.mockReturnValue({
        message: 'Test',
        type: 'human',
        severity: 'warning',
      });

      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      const instance = { $options: { name: 'CreateSecret' } };
      mockApp.config.errorHandler?.(new Error('test'), instance, 'render function');

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          componentName: 'CreateSecret',
          componentInfo: 'render function',
          errorType: 'human',
          errorSeverity: 'warning',
          jurisdiction: 'us',
          planid: 'pro',
          role: 'customer',
        })
      );
    });
  });

  describe('note: service tag is set at scope level', () => {
    // The 'service: web' tag is NOT passed per-event in globalErrorBoundary.
    // It is set once on the Sentry scope in enableDiagnostics.ts (line 323):
    //   scope.setTag('service', 'web');
    // This is correct - all frontend errors are from 'web' service.
    // This test documents this intentional design decision.

    it('does not explicitly pass service tag (scope-level tag from enableDiagnostics)', () => {
      const plugin = createErrorBoundary();
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      const capturedContext = mockCaptureException.mock.calls[0][1];
      // service tag is intentionally NOT in per-event context
      // because it's already set on the Sentry scope
      expect(capturedContext).not.toHaveProperty('service');
    });
  });

  describe('user notification', () => {
    it('calls notify for human-interest errors when notify option provided', () => {
      mockIsOfHumanInterest.mockReturnValue(true);
      mockClassifyError.mockReturnValue({
        message: 'Please try again',
        type: 'human',
        severity: 'warning',
      });

      const mockNotify = vi.fn();
      const plugin = createErrorBoundary({ notify: mockNotify });
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockNotify).toHaveBeenCalledWith('Please try again', 'warning');
    });

    it('does not call notify for technical errors', () => {
      mockIsOfHumanInterest.mockReturnValue(false);
      mockClassifyError.mockReturnValue({
        message: 'Internal error',
        type: 'technical',
        severity: 'error',
      });

      const mockNotify = vi.fn();
      const plugin = createErrorBoundary({ notify: mockNotify });
      plugin.install(mockApp);

      mockApp.config.errorHandler?.(new Error('test'), null, 'setup');

      expect(mockNotify).not.toHaveBeenCalled();
    });
  });
});
