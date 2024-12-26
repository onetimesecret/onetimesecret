import { useExceptionReporting } from '@/composables/useExceptionReporting';
import type { ExceptionData } from '@/types/exceptions'; // Add this type
import api from '@/utils/api';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/utils/api', () => ({
  default: {
    post: vi.fn(),
  },
}));

describe('useExceptionReporting', () => {
  const mockExceptionData: ExceptionData = {
    message: 'Test exception',
    type: 'Error',
    stack: 'Error stack trace',
    url: 'http://localhost:8080',
    line: 1,
    column: 1,
    environment: 'test',
    release: '1.0.0',
  };

  let consoleErrorSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleErrorSpy.mockRestore();
  });

  it('reports exceptions successfully', async () => {
    vi.mocked(api.post).mockResolvedValueOnce({});
    const { reportException } = useExceptionReporting();

    await reportException(mockExceptionData);

    expect(api.post).toHaveBeenCalledWith('/api/v2/exception', mockExceptionData);
    expect(api.post).toHaveBeenCalledTimes(1);
  });

  it('handles API errors gracefully', async () => {
    const apiError = new Error('API Error');
    vi.mocked(api.post).mockRejectedValueOnce(apiError);
    const { reportException } = useExceptionReporting();

    await expect(reportException(mockExceptionData)).resolves.not.toThrow();

    expect(consoleErrorSpy).toHaveBeenCalledWith('Failed to report exception:', apiError);
  });
});
