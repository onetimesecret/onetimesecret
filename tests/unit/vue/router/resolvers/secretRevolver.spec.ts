// tests/unit/vue/router/resolvers/secretResolver.spec.ts

import { useSecretsStore } from '@/stores/secretsStore'
import { resolveSecret } from '@/router/resolvers/secretResolver'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mockRoute = {
  params: {
    secretKey: 'test123'
  },
  meta: {}
}

// Mock the store module
vi.mock('@/stores/secretsStore', () => ({
  useSecretsStore: vi.fn(() => ({
    loadSecret: vi.fn().mockResolvedValue({
      record: {
        key: 'test123',
        secret_key: 'test123',
        is_truncated: false,
        original_size: 100,
        verification: '',
        share_domain: 'example.com',
        is_owner: false,
        has_passphrase: true
      },
      details: {
        continue: false,
        show_secret: false,
        correct_passphrase: false,
        display_lines: 1,
        one_liner: true
      }
    })
  }))
}))

describe('secretResolver', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockRoute.meta = {} // Reset meta for each test
  })

  it('loads secret data and adds to route meta', async () => {
    const next = vi.fn()

    await resolveSecret(
      mockRoute as any,
      {} as any,
      next
    )

    expect(mockRoute.meta.initialData).toBeDefined()
    expect(mockRoute.meta.initialData.status).toBe(200)
    expect(mockRoute.meta.initialData.data.record.key).toBe('test123')
    expect(mockRoute.meta.initialData.error).toBeNull()
    expect(next).toHaveBeenCalled()
  })

  it('handles store errors gracefully', async () => {
    const next = vi.fn()
    const error = new Error('Failed to load')

    // Override store mock for this test
    vi.mocked(useSecretsStore).mockImplementationOnce(() => ({
      loadSecret: vi.fn().mockRejectedValue(error)
    }))

    await resolveSecret(
      mockRoute as any,
      {} as any,
      next
    )

    expect(mockRoute.meta.initialData.status).toBe(500)
    expect(mockRoute.meta.initialData.data).toBeNull()
    expect(mockRoute.meta.initialData.error).toBe('Failed to load')
    expect(next).toHaveBeenCalled()
  })

  it('handles non-Error rejections', async () => {
    const next = vi.fn()

    // Override store mock to reject with non-Error
    vi.mocked(useSecretsStore).mockImplementationOnce(() => ({
      loadSecret: vi.fn().mockRejectedValue('Not found')
    }))

    await resolveSecret(
      mockRoute as any,
      {} as any,
      next
    )

    expect(mockRoute.meta.initialData.status).toBe(404)
    expect(mockRoute.meta.initialData.data).toBeNull()
    expect(mockRoute.meta.initialData.error).toBe('Failed to load secret')
    expect(next).toHaveBeenCalled()
  })

  it('passes validation results through', async () => {
    const next = vi.fn()
    const mockValidatedData = {
      record: {
        key: 'test123',
        secret_key: 'test123',
        // ... other fields
      },
      details: {
        continue: true,
        // ... other fields
      }
    }

    // Override store mock with specific validation result
    vi.mocked(useSecretsStore).mockImplementationOnce(() => ({
      loadSecret: vi.fn().mockResolvedValue(mockValidatedData)
    }))

    await resolveSecret(
      mockRoute as any,
      {} as any,
      next
    )

    expect(mockRoute.meta.initialData.data).toEqual({
      record: mockValidatedData.record,
      details: mockValidatedData.details
    })
    expect(next).toHaveBeenCalled()
  })
})
