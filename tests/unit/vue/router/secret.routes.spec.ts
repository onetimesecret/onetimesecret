// tests/unit/vue/router/secret.routes.spec.ts

import { useSecretsStore } from '@/stores/secretsStore'
import ShowSecretContainer from '@/views/secrets/ShowSecretContainer.vue'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import routes from '@/router/secret.routes'

// Mock the secrets store
vi.mock('@/stores/secretsStore', () => ({
  useSecretsStore: vi.fn(() => ({
    loadSecret: vi.fn().mockResolvedValue({
      record: {
        key: 'test123',
        // ... other record fields
      },
      details: {
        // ... details fields
      }
    })
  }))
}))

describe('Recipient Routes', () => {
  beforeEach(() => {
    // Set up Pinia for each test
    setActivePinia(createPinia())
  })

  describe('Secret Link Route', () => {
    it('should define secret link route correctly', () => {
      const route = routes.find((route) => route.path === '/secret/:secretKey')

      expect(route).toBeDefined()
      expect(route?.component).toBe(ShowSecretContainer) // Changed from components.default
      expect(route?.name).toBe('Secret link')
      expect(route?.props).toBe(true)
    })

    it('should fetch initial secret data before entering the route', async () => {
      const route = routes.find((route) => route.path === '/secret/:secretKey')
      expect(route?.beforeEnter).toBeDefined()

      const mockRoute = {
        params: { secretKey: 'test123' },
        meta: {}
      }
      const mockNext = vi.fn()

      // Get the beforeEnter guard
      const beforeEnter = route?.beforeEnter
      if (!beforeEnter) {
        throw new Error('beforeEnter not defined')
      }

      await beforeEnter(
        mockRoute as any,
        {} as any,
        mockNext
      )

      // Verify the route meta was set correctly
      expect(mockRoute.meta.initialData).toBeDefined()
      expect(mockRoute.meta.initialData.status).toBe(200)
      expect(mockRoute.meta.initialData.error).toBeNull()
      expect(mockNext).toHaveBeenCalled()
    })

    it('should handle error when fetching initial secret data', async () => {
      // Override store mock for error case
      vi.mocked(useSecretsStore).mockImplementationOnce(() => ({
        loadSecret: vi.fn().mockRejectedValue(new Error('Failed to load'))
      }))

      const route = routes.find((route) => route.path === '/secret/:secretKey')
      const mockRoute = {
        params: { secretKey: 'test123' },
        meta: {}
      }
      const mockNext = vi.fn()

      const beforeEnter = route?.beforeEnter
      if (!beforeEnter) {
        throw new Error('beforeEnter not defined')
      }

      await beforeEnter(
        mockRoute as any,
        {} as any,
        mockNext
      )

      expect(mockRoute.meta.initialData.status).toBe(500)
      expect(mockRoute.meta.initialData.data).toBeNull()
      expect(mockRoute.meta.initialData.error).toBe('Failed to load')
      expect(mockNext).toHaveBeenCalled()
    })

    it('should set correct meta data for domain handling', () => {
      const route = routes.find((route) => route.path === '/secret/:secretKey')

      expect(route?.meta).toEqual({
        domain_strategy: window.domain_strategy,
        display_domain: window.display_domain,
        domain_id: window.domain_id,
        site_host: window.site_host
      })
    })
  })
})
