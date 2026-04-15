// src/tests/composables/useAsyncHandler.sentry.spec.ts
//
// Tests for useAsyncHandler Sentry integration - verifies that technical errors
// are captured to Sentry with correct tag context.
//
// Issue: #2964 - Sentry setTag vs setExtras separation
//
// Run:
//   pnpm test src/tests/composables/useAsyncHandler.sentry.spec.ts

import { beforeEach, describe, expect, it, vi } from 'vitest';

// ---------------------------------------------------------------------------
// Mocks - must be hoisted before imports
// ---------------------------------------------------------------------------
const { mockCaptureException, mockIsDiagnosticsEnabled, mockBootstrapStore } = vi.hoisted(() => {
  const mockCaptureException = vi.fn();
  const mockIsDiagnosticsEnabled = vi.fn();
  const mockBootstrapStore = vi.fn();
  return { mockCaptureException, mockIsDiagnosticsEnabled, mockBootstrapStore };
});

vi.mock('@/services/diagnostics.service', () => ({
  captureException: mockCaptureException,
  isDiagnosticsEnabled: mockIsDiagnosticsEnabled,
}));

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: mockBootstrapStore,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

// ---------------------------------------------------------------------------
// Import after mocks
// ---------------------------------------------------------------------------
import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
import { createError } from '@/schemas/errors/classifier';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('useAsyncHandler Sentry integration', () => {
  const mockOptions = {
    notify: vi.fn(),
    log: vi.fn(),
    setLoading: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    // Default: diagnostics disabled
    mockIsDiagnosticsEnabled.mockReturnValue(false);
    mockBootstrapStore.mockReturnValue({
      regions: null,
      organization: null,
      cust: null,
    });
  });

  describe('when diagnostics are enabled', () => {
    beforeEach(() => {
      mockIsDiagnosticsEnabled.mockReturnValue(true);
    });

    it('calls captureException for technical errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const error = new Error('technical error');
      const mockOperation = vi.fn().mockRejectedValue(error);

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledTimes(1);
      expect(mockCaptureException).toHaveBeenCalledWith(error, expect.any(Object));
    });

    it('does not call captureException for human errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const humanError = createError('user message', 'human', 'warning');
      const mockOperation = vi.fn().mockRejectedValue(humanError);

      await wrap(mockOperation);

      // Human errors are not sent to Sentry (only technical errors)
      expect(mockCaptureException).not.toHaveBeenCalled();
    });

    it('passes errorType in context', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const technicalError = createError('system error', 'technical', 'error');
      const mockOperation = vi.fn().mockRejectedValue(technicalError);

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          errorType: 'technical',
        })
      );
    });

    it('passes service tag as "web"', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          service: 'web',
        })
      );
    });

    it('passes jurisdiction from bootstrap store when available', async () => {
      mockBootstrapStore.mockReturnValue({
        regions: { current_jurisdiction: 'EU' },
        organization: null,
        cust: null,
      });

      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          jurisdiction: 'EU',
        })
      );
    });

    it('passes planid from bootstrap store when available', async () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: { planid: 'enterprise_v2' },
        cust: null,
      });

      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          planid: 'enterprise_v2',
        })
      );
    });

    it('passes role from bootstrap store when available', async () => {
      mockBootstrapStore.mockReturnValue({
        regions: null,
        organization: null,
        cust: { role: 'colonel' },
      });

      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          role: 'colonel',
        })
      );
    });

    it('passes all available context tags together', async () => {
      mockBootstrapStore.mockReturnValue({
        regions: { current_jurisdiction: 'us' },
        organization: { planid: 'pro' },
        cust: { role: 'customer' },
      });

      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          errorType: 'technical',
          service: 'web',
          jurisdiction: 'us',
          planid: 'pro',
          role: 'customer',
        })
      );
    });

    it('handles undefined bootstrap values gracefully', async () => {
      mockBootstrapStore.mockReturnValue({
        regions: undefined,
        organization: undefined,
        cust: undefined,
      });

      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      // Should still capture exception, just without optional tags
      expect(mockCaptureException).toHaveBeenCalledTimes(1);
      const capturedContext = mockCaptureException.mock.calls[0][1];
      expect(capturedContext).toHaveProperty('errorType');
      expect(capturedContext).toHaveProperty('service', 'web');
    });
  });

  describe('when diagnostics are disabled', () => {
    beforeEach(() => {
      mockIsDiagnosticsEnabled.mockReturnValue(false);
    });

    it('does not call captureException', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      await wrap(mockOperation);

      expect(mockCaptureException).not.toHaveBeenCalled();
    });
  });
});
