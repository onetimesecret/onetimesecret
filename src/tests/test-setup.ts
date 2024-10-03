import { vi } from 'vitest'

// Mock global objects that JSDOM doesn't support
global.fetch = vi.fn()
global.Request = vi.fn()
global.Response = vi.fn()
