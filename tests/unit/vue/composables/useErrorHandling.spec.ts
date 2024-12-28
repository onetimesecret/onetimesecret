import { useErrorHandler } from '@/composables/useErrorHandler';
import type { ApplicationError } from '@/schemas/errors';
import { createError } from '@/schemas/errors/factory';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// Mock the error classifier
vi.mock('@/schemas/errors/classifier', () => ({
  classifyError: (error: unknown) => {
    if ((error as ApplicationError).type) {
      return error as ApplicationError;
    }
    return createError(error instanceof Error ? error.message : String(error));
  },
}));

describe('useErrorHandler', () => {
  const mockOptions = {
    notify: vi.fn(),
    log: vi.fn(),
    setLoading: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('withErrorHandling', () => {
    it('successfully executes and returns operation result', async () => {
      const { withErrorHandling } = useErrorHandler(mockOptions);
      const mockOperation = vi.fn().mockResolvedValue('success');

      const result = await withErrorHandling(mockOperation);

      expect(result).toBe('success');
      expect(mockOptions.setLoading).toHaveBeenCalledWith(true);
      expect(mockOptions.setLoading).toHaveBeenCalledWith(false);
      expect(mockOptions.notify).not.toHaveBeenCalled();
      expect(mockOptions.log).not.toHaveBeenCalled();
    });

    it('manages loading state even when operation fails', async () => {
      const { withErrorHandling } = useErrorHandler(mockOptions);
      const mockOperation = vi.fn().mockRejectedValue(new Error('Operation failed'));

      await expect(withErrorHandling(mockOperation)).rejects.toThrow();

      expect(mockOptions.setLoading).toHaveBeenCalledWith(true);
      expect(mockOptions.setLoading).toHaveBeenCalledWith(false);
    });

    it('handles human errors with notification', async () => {
      const { withErrorHandling } = useErrorHandler(mockOptions);
      const humanError = createError('User-facing error', 'human', 'error');
      const mockOperation = vi.fn().mockRejectedValue(humanError);

      await expect(withErrorHandling(mockOperation)).rejects.toThrow(humanError);

      expect(mockOptions.notify).toHaveBeenCalledWith('User-facing error', 'error');
      expect(mockOptions.log).toHaveBeenCalledWith(humanError);
    });

    it('works without optional handlers', async () => {
      const { withErrorHandling } = useErrorHandler({});
      const mockOperation = vi.fn().mockResolvedValue('success');

      const result = await withErrorHandling(mockOperation);

      expect(result).toBe('success');
    });

    it('rethrows classified errors', async () => {
      const { withErrorHandling } = useErrorHandler(mockOptions);
      const mockError = new Error('Raw error');
      const mockOperation = vi.fn().mockRejectedValue(mockError);

      await expect(withErrorHandling(mockOperation)).rejects.toMatchObject({
        message: 'Raw error',
        type: 'technical',
        severity: 'error',
      });
    });
  });
});
