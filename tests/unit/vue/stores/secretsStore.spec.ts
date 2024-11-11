// tests/unit/vue/stores/secretStore.spec.ts

import { createApi } from '@/utils/api'
import { useSecretsStore } from '@/stores/secretsStore'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { AxiosInstance } from 'axios';

// Mock createApi before it's used
vi.mock('@/utils/api', () => ({
  createApi: vi.fn(() => ({
    get: vi.fn().mockResolvedValue({ data: mockSecretResponse }),
    post: vi.fn().mockResolvedValue({ data: mockSecretRevealed })
  }))
}))

// TODO: ReferenceError: Cannot access 'mockSecretResponse' before initialization ?

// Mock API responses after mocking the api itself
const mockSecretResponse = {
  success: true,
  record: {
    key: 'abc123',
    secret_key: 'abc123',
    is_truncated: false,
    original_size: 100,
    verification: '',
    share_domain: 'example.com',
    is_owner: false,
    has_passphrase: true,
  },
  details: {
    continue: false,
    show_secret: false,
    correct_passphrase: false,
    display_lines: 1,
    one_liner: true
  }
}

const mockSecretRevealed = {
  ...mockSecretResponse,
  record: {
    ...mockSecretResponse.record,
    secret_value: 'revealed secret'
  },
  details: {
    ...mockSecretResponse.details,
    show_secret: true,
    correct_passphrase: true
  }
}

describe('secretsStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('initializes with empty state', () => {
    const store = useSecretsStore()
    expect(store.record).toBeNull()
    expect(store.details).toBeNull()
    expect(store.isLoading).toBe(false)
    expect(store.error).toBeNull()
  })

  describe('loadSecret', () => {
    it('loads initial secret details successfully', async () => {
      const store = useSecretsStore()
      await store.loadSecret('abc123')

      expect(store.record).toEqual(mockSecretResponse.record)
      expect(store.details).toEqual(mockSecretResponse.details)
      expect(store.isLoading).toBe(false)
      expect(store.error).toBeNull()
    })

    it('handles validation errors', async () => {
      const store = useSecretsStore()
      vi.mocked(createApi).mockReturnValue({
        get: vi.fn().mockResolvedValue({ data: { invalid: 'data' } }),
        post: vi.fn()
      } as unknown as AxiosInstance)

      await expect(store.loadSecret('abc123')).rejects.toThrow()
      expect(store.error).toBe('Invalid server response')
    })

    it('handles network errors', async () => {
      const store = useSecretsStore()
      vi.mocked(createApi).mockReturnValue({
        get: vi.fn().mockRejectedValue(new Error('Network error')),
        post: vi.fn()
      } as unknown as AxiosInstance)

      await expect(store.loadSecret('abc123')).rejects.toThrow('Network error')
      expect(store.error).toBe('Network error')
    })
  })

  describe('revealSecret', () => {
    it('reveals secret with passphrase', async () => {
      const store = useSecretsStore()
      await store.revealSecret('abc123', 'password')

      expect(store.record?.secret_value).toBe('revealed secret')
      expect(store.details?.show_secret).toBe(true)
      expect(store.isLoading).toBe(false)
      expect(store.error).toBeNull()
    })

    it('preserves state on error', async () => {
      const store = useSecretsStore()
      // Load initial state
      await store.loadSecret('abc123')
      const initialState = { record: store.record, details: store.details }

      // Force error
      vi.mocked(createApi).mockReturnValue({
        get: vi.fn(),
        post: vi.fn().mockRejectedValue(new Error('Invalid passphrase'))
      } as unknown as AxiosInstance)

      await expect(store.revealSecret('abc123', 'wrong')).rejects.toThrow()
      expect(store.record).toEqual(initialState.record)
      expect(store.details).toEqual(initialState.details)
    })
  })

  describe('clearSecret', () => {
    it('resets store state', async () => {
      const store = useSecretsStore()
      await store.loadSecret('abc123')
      store.clearSecret()

      expect(store.record).toBeNull()
      expect(store.details).toBeNull()
      expect(store.error).toBeNull()
    })
  })
})
