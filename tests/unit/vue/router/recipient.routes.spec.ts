import { describe, it, expect, vi } from 'vitest'
import { RouteRecordRaw, RouteLocationNormalized, NavigationGuardNext, NavigationGuard } from 'vue-router'
import dashboardRoutes from '@/router/dashboard.routes'
import { fetchInitialSecret } from '@/api/secrets'
import { AsyncDataResult, SecretDataApiResponse } from '@/types'

vi.mock('@/api/secrets', () => ({
  fetchInitialSecret: vi.fn(),
}))

describe('Recipient Routes', () => {
  describe('Secret Link Route', () => {
    it('should define secret link route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/secret/:secretKey')
      expect(route).toBeDefined()
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(false)
      expect(route?.meta?.layoutProps?.displayNavigation).toBe(false)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(false)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(false)
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true)
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(true)
    })

    it('should fetch initial secret data before entering the route', async () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/secret/:secretKey')
      const next = vi.fn() as NavigationGuardNext
      const secretKey = 'test-secret-key'
      const initialData: AsyncDataResult<SecretDataApiResponse> = {
        data: {
          success: true,
          record: {
            identifier: 'test-id',
            created: '2023-01-01T00:00:00Z',
            updated: '2023-01-01T00:00:00Z',
            key: secretKey,
            secret_key: secretKey,
            secret_shortkey: 'test-short',
            is_truncated: false,
            original_size: 100,
            verification: 'test-verification',
            share_domain: 'example.com',
            is_owner: false,
            has_passphrase: false,
            secret_value: 'test-secret'
          }
        },
        error: null,
        status: 200
      }

      vi.mocked(fetchInitialSecret).mockResolvedValue(initialData)

      const mockTo = {
        params: { secretKey },
        name: 'secret',
        path: `/secret/${secretKey}`,
        hash: '',
        query: {},
        fullPath: `/secret/${secretKey}`,
        matched: [],
        meta: {},
        redirectedFrom: undefined
      } as RouteLocationNormalized

      const mockFrom = {
        name: 'home',
        path: '/',
        hash: '',
        query: {},
        params: {},
        fullPath: '/',
        matched: [],
        meta: {},
        redirectedFrom: undefined
      } as RouteLocationNormalized

      if (route?.beforeEnter) {
        const guard = (route.beforeEnter as NavigationGuard).bind(undefined)
        await guard(mockTo, mockFrom, next)
      }

      expect(fetchInitialSecret).toHaveBeenCalledWith(secretKey)
      expect(next).toHaveBeenCalled()
    })

    it('should handle error when fetching initial secret data', async () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/secret/:secretKey')
      const next = vi.fn() as NavigationGuardNext
      const secretKey = 'test-secret-key'
      const error = new Error('Failed to fetch initial page data')

      vi.mocked(fetchInitialSecret).mockRejectedValue(error)
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

      const mockTo = {
        params: { secretKey },
        name: 'secret',
        path: `/secret/${secretKey}`,
        hash: '',
        query: {},
        fullPath: `/secret/${secretKey}`,
        matched: [],
        meta: {},
        redirectedFrom: undefined
      } as RouteLocationNormalized

      const mockFrom = {
        name: 'home',
        path: '/',
        hash: '',
        query: {},
        params: {},
        fullPath: '/',
        matched: [],
        meta: {},
        redirectedFrom: undefined
      } as RouteLocationNormalized

      if (route?.beforeEnter) {
        const guard = (route.beforeEnter as NavigationGuard).bind(undefined)
        await guard(mockTo, mockFrom, next)
      }

      expect(fetchInitialSecret).toHaveBeenCalledWith(secretKey)
      expect(consoleSpy).toHaveBeenCalledWith('Error fetching initial page data:', error)
      expect(next).toHaveBeenCalledWith(new Error('Failed to fetch initial page data'))
    })
  })
})
