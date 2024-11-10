import { describe, it, expect, vi } from 'vitest'
import { RouteRecordRaw, RouteLocationNormalized } from 'vue-router'
import dashboardRoutes from '@/router/dashboard.routes'
import { fetchInitialSecret } from '@/api/secrets'
import { AsyncDataResult, SecretDataApiResponse } from '@/types/api/responses'

vi.mock('@/api/secrets', () => ({
  fetchInitialSecret: vi.fn(),
}))

describe('Dashboard Routes', () => {
  describe('Dashboard Route', () => {
    it('should define dashboard route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/dashboard')
      expect(route).toBeDefined()
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(typeof route?.components?.default).toBe('object') // Check for object type
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })

  describe('Recents Route', () => {
    it('should define recents route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/recent')
      expect(route).toBeDefined()
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(typeof route?.components?.default).toBe('object') // Check for object type
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })

  describe('Account Domains Route', () => {
    it('should define account domains route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/account/domains')
      expect(route).toBeDefined()
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(typeof route?.components?.default).toBe('object') // Check for object type
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })



  describe('Metadata Link Route', () => {
    it('should define metadata link route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/private/:metadataKey')
      expect(route).toBeDefined()
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true)
      expect(route?.meta?.layoutProps?.displayNavigation).toBe(true)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true)
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true)
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(true)
    })
  })

  describe('Burn Secret Route', () => {
    it('should define burn secret route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/private/:metadataKey/burn')
      expect(route).toBeDefined()
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(false)
      expect(route?.meta?.layoutProps?.displayNavigation).toBe(false)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(false)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(false)
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true)
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(true)
    })
  })
})
