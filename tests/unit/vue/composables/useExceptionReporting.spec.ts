import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { useExceptionReporting } from '@/composables/useExceptionReporting'
import axios from 'axios'

vi.mock('axios')

describe('useExceptionReporting', () => {
  const mockExceptionData = {
    message: 'Test exception',
    type: 'Error',
    stack: 'Error stack trace',
    url: 'http://localhost:8080',
    line: 1,
    column: 1,
    environment: 'test',
    release: '1.0.0'
  }

  let consoleErrorMock: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    vi.clearAllMocks()
    consoleErrorMock = vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    consoleErrorMock.mockRestore()
  })

  it('should report exceptions correctly', async () => {
    vi.mocked(axios.post).mockResolvedValueOnce({})
    const { reportException } = useExceptionReporting()

    await reportException(mockExceptionData)

    expect(axios.post).toHaveBeenCalledWith('/api/v2/exception', mockExceptionData)
    expect(axios.post).toHaveBeenCalledTimes(1)
  })

  it('should handle exceptions gracefully', async () => {
    vi.mocked(axios.post).mockRejectedValueOnce(new Error('API Error'))
    const { reportException } = useExceptionReporting()

    await expect(reportException(mockExceptionData)).resolves.not.toThrow()

    expect(console.error).toHaveBeenCalledWith('Failed to report exception:', expect.any(Error))
  })
})
