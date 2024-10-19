import { useCsrfStore } from '@/stores/csrfStore'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

describe('CSRF Store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
    vi.spyOn(window, 'setInterval')
    vi.spyOn(window, 'clearInterval')
    vi.spyOn(console, 'error').mockImplementation(() => { })
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it('initializes with correct values', () => {
    const store = useCsrfStore()
    expect(store.shrimp).toBe('')
    expect(store.isValid).toBe(false)
    expect(store.intervalChecker).toBeNull()
  })

  it('updates shrimp correctly', () => {
    const store = useCsrfStore()
    const newShrimp = 'new-shrimp-token'
    store.updateShrimp(newShrimp)
    expect(store.shrimp).toBe(newShrimp)
    expect(window.shrimp).toBe(newShrimp)
    expect(store.isValid).toBe(true)
  })

  it('checks shrimp validity successfully', async () => {
    const store = useCsrfStore()
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ isValid: true, shrimp: 'new-shrimp' })
    })
    vi.stubGlobal('fetch', mockFetch)

    await store.checkShrimpValidity()

    expect(store.isValid).toBe(true)
    expect(store.shrimp).toBe('new-shrimp')
    expect(mockFetch).toHaveBeenCalledWith('/api/v2/validate-shrimp', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'O-Shrimp': 'new-shrimp-token'
      }
    })

    vi.unstubAllGlobals()
  })

  it('handles shrimp validity check failure', async () => {
    const store = useCsrfStore()
    const mockFetch = vi.fn().mockResolvedValue({
      ok: false
    })
    vi.stubGlobal('fetch', mockFetch)

    await store.checkShrimpValidity()

    expect(store.isValid).toBe(false)

    vi.unstubAllGlobals()
  })

  it('handles network error during shrimp validity check', async () => {
    const store = useCsrfStore()
    const mockFetch = vi.fn().mockRejectedValue(new Error('Network error'))
    vi.stubGlobal('fetch', mockFetch)

    await store.checkShrimpValidity()

    expect(store.isValid).toBe(false)
    expect(console.error).toHaveBeenCalledWith('Failed to check CSRF token validity:', expect.any(Error))

    vi.unstubAllGlobals()
  })

  it('starts periodic check correctly', () => {
    const store = useCsrfStore()
    const checkShrimpValiditySpy = vi.spyOn(store, 'checkShrimpValidity')

    store.startPeriodicCheck(30000)

    expect(window.setInterval).toHaveBeenCalledWith(expect.any(Function), 30000)
    expect(store.intervalChecker).not.toBeNull()

    vi.advanceTimersByTime(30000)
    expect(checkShrimpValiditySpy).toHaveBeenCalled()
  })

  it('stops periodic check correctly', () => {
    const store = useCsrfStore()
    store.startPeriodicCheck()
    expect(store.intervalChecker).not.toBeNull()

    store.stopPeriodicCheck()

    expect(window.clearInterval).toHaveBeenCalled()
    expect(store.intervalChecker).toBeNull()
  })

  it('restarts periodic check when called multiple times', () => {
    const store = useCsrfStore()
    store.startPeriodicCheck(30000)
    const firstInterval = store.intervalChecker

    store.startPeriodicCheck(60000)
    const secondInterval = store.intervalChecker

    expect(firstInterval).not.toBe(secondInterval)
    expect(window.clearInterval).toHaveBeenCalledWith(firstInterval)
    expect(window.setInterval).toHaveBeenCalledWith(expect.any(Function), 60000)
  })

  it('uses default interval when not specified', () => {
    const store = useCsrfStore()
    store.startPeriodicCheck()

    expect(window.setInterval).toHaveBeenCalledWith(expect.any(Function), 60000)
  })

  it('initializes with window.shrimp if available', () => {
    vi.stubGlobal('shrimp', 'initial-shrimp')
    const store = useCsrfStore()

    expect(store.shrimp).toBe('initial-shrimp')

    vi.unstubAllGlobals()
  })
})
