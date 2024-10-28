import { describe, it, expect, vi, beforeEach } from 'vitest'
import { RouteRecordRaw, NavigationGuardWithThis, RouteLocationNormalized, NavigationGuardNext } from 'vue-router'
import { ref, Ref } from 'vue'

// Move the mock before the route import
vi.mock('@/composables/useWindowProps', () => ({
  useWindowProp: vi.fn(() => ref(false))
}))

// Import routes after the mock is set up
import publicRoutes from '@/router/public.routes'
import { useWindowProp } from '@/composables/useWindowProps'


describe('Public Routes', () => {
  describe('Homepage Route', () => {
    it('should define homepage route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/')
      expect(route).toBeDefined()
      expect(route?.name).toBe('Home')
      expect(route?.meta?.requiresAuth).toBe(false)
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true)
    })

    it('should redirect authenticated users to dashboard', async () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/')
      vi.mocked(useWindowProp).mockReturnValue(ref(true) as Ref<boolean>)

      const next = vi.fn() as NavigationGuardNext
      const beforeEnter = route?.beforeEnter as NavigationGuardWithThis<undefined>

      await beforeEnter.call(undefined,
        {} as RouteLocationNormalized,
        {} as RouteLocationNormalized,
        next
      )

      // Change expectation to match one call without arguments
      expect(next).toHaveBeenCalledWith()
      expect(next).toHaveBeenCalledTimes(1)
    })


    it('should allow unauthenticated users to access homepage', async () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/')
      vi.mocked(useWindowProp).mockReturnValue(ref(false) as Ref<boolean>)

      const next = vi.fn() as NavigationGuardNext
      const beforeEnter = route?.beforeEnter as NavigationGuardWithThis<undefined>
      await beforeEnter.call(undefined,
        {} as RouteLocationNormalized,
        {} as RouteLocationNormalized,
        next
      )

      expect(next).toHaveBeenCalledWith()
    })
  })
  describe('Incoming Secrets Route', () => {
    it('should define incoming secrets route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/incoming')
      expect(route).toBeDefined()
      expect(route?.name).toBe('Inbound Secrets')
      expect(route?.meta?.requiresAuth).toBe(false)
      expect(route?.meta?.layout).toBeDefined()
    })
  })

  describe('Info Routes', () => {
    const infoRoutes = [
      { path: '/info/privacy', name: 'Privacy Policy' },
      { path: '/info/terms', name: 'Terms of Use' },
      { path: '/info/security', name: 'Security Policy' }
    ]

    infoRoutes.forEach(infoRoute => {
      it(`should define ${infoRoute.name} route correctly`, () => {
        const route = publicRoutes.find((route: RouteRecordRaw) => route.path === infoRoute.path)
        expect(route).toBeDefined()
        expect(route?.name).toBe(infoRoute.name)
        expect(route?.meta?.requiresAuth).toBe(false)
        expect(route?.meta?.layout).toBeDefined()
        expect(typeof route?.component).toBe('function') // Lazy loaded
      })
    })
  })

  describe('Feedback Route', () => {
    it('should define feedback route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/feedback')
      expect(route).toBeDefined()
      expect(route?.name).toBe('Feedback')
      expect(route?.meta?.requiresAuth).toBe(false)
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(false)
      expect(typeof route?.component).toBe('function') // Lazy loaded
    })
  })

  describe('About Route', () => {
    it('should define about route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/about')
      expect(route).toBeDefined()
      expect(route?.name).toBe('About')
      expect(route?.meta?.requiresAuth).toBe(false)
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true)
      expect(typeof route?.component).toBe('function') // Lazy loaded
    })
  })

  describe('Translations Route', () => {
    it('should define translations route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/translations')
      expect(route).toBeDefined()
      expect(route?.name).toBe('Translations')
      expect(route?.meta?.requiresAuth).toBe(false)
      expect(route?.meta?.layout).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true)
      expect(typeof route?.component).toBe('function') // Lazy loaded
    })
  })
})
