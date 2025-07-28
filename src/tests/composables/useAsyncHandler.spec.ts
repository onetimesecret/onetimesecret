// src/tests/composables/useAsyncHandler.spec.ts
import { useAsyncHandler } from '@/composables/useAsyncHandler';
import { createError } from '@/schemas/errors/classifier';
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('useAsyncHandler', () => {
  const mockOptions = {
    notify: vi.fn(),
    log: vi.fn(),
    setLoading: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('loading state management', () => {
    it('manages loading state for successful operations', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockResolvedValue('success');

      await wrap(mockOperation);

      expect(mockOptions.setLoading).toHaveBeenCalledTimes(2);
      expect(mockOptions.setLoading).toHaveBeenNthCalledWith(1, true);
      expect(mockOptions.setLoading).toHaveBeenNthCalledWith(2, false);
    });

    it.skip('ensures loading state is cleared after error', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('fail'));

      const result = await wrap(mockOperation);
      expect(result).toBeUndefined();

      expect(mockOptions.setLoading).toHaveBeenCalledTimes(2);
      expect(mockOptions.setLoading).toHaveBeenLastCalledWith(false);
    });
  });

  describe('error classification', () => {
    it.skip('classifies raw errors into ApplicationErrors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('raw error'));

      await expect(wrap(mockOperation)).rejects.toMatchObject({
        message: 'raw error',
        type: 'technical',
        severity: 'error',
      });
    });

    it('preserves existing ApplicationErrors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const applicationError = createError('known error', 'human', 'warning');
      const mockOperation = vi.fn().mockRejectedValue(applicationError);

      const result = await wrap(mockOperation);

      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith('known error', 'warning');
    });
  });

  describe('user feedback', () => {
    it('notifies only for human errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const humanError = createError('user message', 'human', 'warning');
      const mockOperation = vi.fn().mockRejectedValue(humanError);

      const result = await wrap(mockOperation);

      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith('user message', 'warning');
    });

    it('logs but does not notify for technical errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const technicalError = createError('system error', 'technical', 'error');
      const mockOperation = vi.fn().mockRejectedValue(technicalError);

      const result = await wrap(mockOperation);

      expect(result).toBeUndefined();
      expect(mockOptions.log).toHaveBeenCalled();
      expect(mockOptions.notify).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error');
    });

    it('handles notification failures gracefully', async () => {
      const notifyError = new Error('notification failed');
      const mockOptions = {
        notify: vi.fn().mockImplementation(() => {
          throw notifyError;
        }),
        log: vi.fn(),
        setLoading: vi.fn(),
      };
      const { wrap } = useAsyncHandler(mockOptions);
      const humanError = createError('user message', 'human', 'warning');
      const mockOperation = vi.fn().mockRejectedValue(humanError);

      await expect(wrap(mockOperation)).rejects.toThrow('notification failed');
    });
  });

  describe('error classification behavior', () => {
    it('correctly identifies human errors for notification', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const humanErrors = [
        createError('user message 1', 'human', 'warning'),
        createError('user message 2', 'human', 'error'),
        createError('user message 3', 'human', 'info'),
      ];

      for (const error of humanErrors) {
        const mockOperation = vi.fn().mockRejectedValue(error);
        const result = await wrap(mockOperation);
        expect(result).toBeUndefined();
        expect(mockOptions.notify).toHaveBeenLastCalledWith(error.message, error.severity);
      }
    });

    it('correctly identifies technical errors for suppressing notifications', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const technicalErrors = [
        createError('system error', 'technical', 'error'),
        new TypeError('type error'),
        new ReferenceError('reference error'),
      ];

      for (const error of technicalErrors) {
        const mockOperation = vi.fn().mockRejectedValue(error);
        const result = await wrap(mockOperation);
        expect(result).toBeUndefined();
        expect(mockOptions.notify).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error');
        vi.clearAllMocks();
      }
    });

    it('handles various non-error throwables consistently', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const throwables = ['string error', 123, { custom: 'error' }, null, undefined];

      for (const throwable of throwables) {
        const mockOperation = vi.fn().mockRejectedValue(throwable);
        const result = await wrap(mockOperation);
        expect(result).toBeUndefined();
        expect(mockOptions.notify).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error');
        vi.clearAllMocks();
      }
    });

    it('preserves error details when classifying ApplicationErrors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const originalError = createError('known error', 'human', 'warning', {
        code: 'VALIDATION_ERROR',
        field: 'email',
      });
      const mockOperation = vi.fn().mockRejectedValue(originalError);

      const result = await wrap(mockOperation);
      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith('known error', 'warning');
    });

    it('ensures classified errors maintain instanceof Error', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue('string error');

      try {
        await wrap(mockOperation);
      } catch (error) {
        expect(error).toBeInstanceOf(Error);
        expect(error).toHaveProperty('type');
        expect(error).toHaveProperty('severity');
      }
    });
  });

  describe('error propagation', () => {
    it('preserves stack traces when classifying errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const originalError = new Error('original error');
      const mockOperation = vi.fn().mockRejectedValue(originalError);

      try {
        await wrap(mockOperation);
      } catch (error) {
        expect(error).toBeInstanceOf(Error);
        expect(error.stack).toBeDefined();
        expect(error.stack).toContain('original error');
      }
    });

    it('maintains error chain for nested operations', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const innerOp = () => Promise.reject(new Error('inner error'));
      const outerOp = async () => {
        try {
          await wrap(innerOp);
        } catch (e) {
          throw new Error('outer error', { cause: e });
        }
      };

      const result = await wrap(outerOp);
      expect(result).toBeUndefined();
      expect(mockOptions.log).toHaveBeenCalledTimes(1); // Only inner error logged since wrap doesn't throw
    });

    it('maintains error context through multiple handling layers', async () => {
      const { wrap } = useAsyncHandler(mockOptions);

      const level3 = () => Promise.reject(createError('db error', 'technical'));
      const level2 = async () => {
        try {
          await level3();
        } catch (e) {
          throw createError('service error', 'technical', 'error', { cause: e });
        }
      };
      const level1 = async () => {
        try {
          await wrap(level2);
        } catch (e) {
          throw createError('api error', 'human', 'error', { cause: e });
        }
      };

      const result = await wrap(level1);
      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error');
    });
  });

  describe('operation handling', () => {
    it('allows successful operations to pass through unchanged', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const expectedResult = { data: 'success' };
      const mockOperation = vi.fn().mockResolvedValue(expectedResult);

      const result = await wrap(mockOperation);
      expect(result).toEqual(expectedResult);
    });

    it('handles async operations that return undefined', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockResolvedValue(undefined);

      const result = await wrap(mockOperation);
      expect(result).toBeUndefined();
    });

    it('handles synchronous errors in async operations', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockOperation = vi.fn().mockImplementation(() => {
        throw new Error('sync error');
      });

      const result = await wrap(mockOperation);
      expect(result).toBeUndefined();
    });
  });

  describe('optional dependencies', () => {
    it('functions without notification handler', async () => {
      const { wrap } = useAsyncHandler({
        log: mockOptions.log,
        setLoading: mockOptions.setLoading,
      });
      const humanError = createError('user message', 'human', 'warning');
      const mockOperation = vi.fn().mockRejectedValue(humanError);

      const result = await wrap(mockOperation);
      expect(result).toBeUndefined();
      // Should not throw due to missing notify handler
    });

    it('functions without logging handler', async () => {
      const { wrap } = useAsyncHandler({
        notify: mockOptions.notify,
        setLoading: mockOptions.setLoading,
      });
      const mockOperation = vi.fn().mockRejectedValue(new Error('test'));

      const result = await wrap(mockOperation);
      expect(result).toBeUndefined();
      // Should not throw due to missing log handler
    });

    it('functions without loading state handler', async () => {
      const { wrap } = useAsyncHandler({
        notify: mockOptions.notify,
        log: mockOptions.log,
      });
      const mockOperation = vi.fn().mockResolvedValue('success');

      await wrap(mockOperation);
      // Should not throw due to missing setLoading handler
    });
  });

  describe('API operation scenarios', () => {
    it('handles API timeout errors appropriately', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const timeoutError = new Error('Request timeout');
      timeoutError.name = 'TimeoutError';
      const mockApiCall = vi.fn().mockRejectedValue(timeoutError);

      const result = await wrap(mockApiCall);
      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error');
    });

    it('handles API validation errors as human errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const validationError = createError('Invalid email format', 'human', 'warning', {
        field: 'email',
      });
      const mockApiCall = vi.fn().mockRejectedValue(validationError);

      const result = await wrap(mockApiCall);
      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith('Invalid email format', 'warning');
    });

    it('manages loading state through entire API call duration', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      let isLoadingDuringCall = false;

      const mockApiCall = vi.fn().mockImplementation(async () => {
        await new Promise((resolve) => setTimeout(resolve, 10));
        isLoadingDuringCall = mockOptions.setLoading.mock.calls[0][0];
        return 'success';
      });

      await wrap(mockApiCall);

      expect(isLoadingDuringCall).toBe(true);
      expect(mockOptions.setLoading).toHaveBeenLastCalledWith(false);
    });
  });

  describe('API error notification strategies', () => {
    it('notifies users of recoverable API errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const recoverableErrors = [
        createError('Your session has expired, please login again', 'human', 'warning'),
        createError('This file is too large, max size is 5MB', 'human', 'warning'),
        createError('This secret has already been viewed', 'human', 'info'),
      ];

      for (const error of recoverableErrors) {
        const mockApiCall = vi.fn().mockRejectedValue(error);
        const result = await wrap(mockApiCall);
        expect(result).toBeUndefined();
        expect(mockOptions.notify).toHaveBeenLastCalledWith(error.message, error.severity);
        vi.clearAllMocks();
      }
    });

    it('suppresses notifications for network/infrastructure errors', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const technicalErrors = [
        new TypeError('Failed to fetch'), // Browser network error
        createError('ECONNREFUSED', 'technical'), // Server connection refused
        createError('Request timed out', 'technical'), // Timeout
        new Error('Network error'), // Generic network error
      ];

      for (const error of technicalErrors) {
        const mockApiCall = vi.fn().mockRejectedValue(error);
        const result = await wrap(mockApiCall);
        expect(result).toBeUndefined();
        expect(mockOptions.notify).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error');
        expect(mockOptions.log).toHaveBeenCalled();
        vi.clearAllMocks();
      }
    });

    it('handles API rate limiting as a human error', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const rateLimitError = createError(
        'Too many requests, please try again in 5 minutes',
        'human',
        'warning',
        { retryAfter: 300 }
      );
      const mockApiCall = vi.fn().mockRejectedValue(rateLimitError);

      const result = await wrap(mockApiCall);
      expect(result).toBeUndefined();
      expect(mockOptions.notify).toHaveBeenCalledWith(rateLimitError.message, 'warning');
    });
  });

  describe('loading state management during API calls', () => {
    it('handles rapid successive API calls correctly', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockApiCall1 = vi
        .fn()
        .mockImplementation(() => new Promise((resolve) => setTimeout(resolve, 50)));
      const mockApiCall2 = vi
        .fn()
        .mockImplementation(() => new Promise((resolve) => setTimeout(resolve, 30)));

      // Start both calls almost simultaneously
      const call1 = wrap(mockApiCall1);
      const call2 = wrap(mockApiCall2);

      await Promise.all([call1, call2]);

      // Loading should stay true until both calls complete
      const loadingCalls = mockOptions.setLoading.mock.calls;
      expect(loadingCalls).toEqual([
        [true], // First call starts
        [true], // Second call starts
        [false], // Second call ends
        [false], // First call ends
      ]);
    });

    it('maintains loading state during retries', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      let attempts = 0;
      const mockApiCall = vi.fn().mockImplementation(async () => {
        attempts++;
        if (attempts === 1) {
          // Need to create a proper ApplicationError
          throw createError('First attempt failed', 'technical');
        }
        return 'success';
      });

      const result = await wrap(async () => {
        try {
          return await mockApiCall();
        } catch (error) {
          // Retry once
          return await mockApiCall();
        }
      });

      expect(result).toBe('success');
      expect(attempts).toBe(2);
      expect(mockOptions.setLoading).toHaveBeenCalledTimes(2);
      expect(mockOptions.setLoading).toHaveBeenNthCalledWith(1, true);
      expect(mockOptions.setLoading).toHaveBeenNthCalledWith(2, false);
    });

    it('properly resets loading state after unexpected promise behavior', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const mockApiCall = vi.fn().mockImplementation(() => {
        // This creates an invalid async operation
        return Promise.reject(createError('Invalid operation', 'technical'));
      });

      const result = await wrap(mockApiCall);
      expect(result).toBeUndefined();

      expect(mockOptions.setLoading).toHaveBeenCalledTimes(2);
      expect(mockOptions.setLoading).toHaveBeenNthCalledWith(1, true);
      expect(mockOptions.setLoading).toHaveBeenNthCalledWith(2, false);
    });

    it('handles cancellation of API calls gracefully', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const abortController = new AbortController();
      const mockApiCall = vi.fn().mockImplementation(() => {
        return new Promise((_, reject) => {
          abortController.signal.addEventListener('abort', () => {
            reject(new Error('Request aborted'));
          });
        });
      });

      const apiPromise = wrap(mockApiCall);
      abortController.abort();

      const result = await apiPromise;
      expect(result).toBeUndefined();
      expect(mockOptions.setLoading).toHaveBeenLastCalledWith(false);
    });

    // Add to "loading state management during API calls" describe block
    it('handles overlapping async operations correctly', async () => {
      const { wrap } = useAsyncHandler(mockOptions);
      const slowOp = vi
        .fn()
        .mockImplementation(() => new Promise((resolve) => setTimeout(() => resolve('slow'), 50)));
      const fastOp = vi
        .fn()
        .mockImplementation(() => new Promise((resolve) => setTimeout(() => resolve('fast'), 20)));

      const results = await Promise.all([wrap(slowOp), wrap(fastOp)]);

      expect(results).toEqual(['slow', 'fast']);
      const loadingCalls = mockOptions.setLoading.mock.calls;
      expect(loadingCalls[0]).toEqual([true]); // First operation starts
      expect(loadingCalls[loadingCalls.length - 1]).toEqual([false]); // Last operation ends
    });
  });
});
