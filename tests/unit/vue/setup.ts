import { vi } from 'vitest'

// Mock global objects that JSDOM doesn't support
global.fetch = vi.fn()

// Create a mock for the Response object
const mockResponse = {
  error: vi.fn(),
  json: vi.fn(),
  redirect: vi.fn(),
  prototype: Response.prototype
} as unknown as typeof Response;

global.Request = vi.fn()
global.Response = mockResponse
