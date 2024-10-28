import { describe, it, expect, beforeEach } from 'vitest'
import { RouteRecordRaw } from 'vue-router'
import productRoutes from '@/router/product.routes'
import WideLayout from '@/layouts/WideLayout.vue'

describe('Product Routes', () => {
  describe('Pricing Route', () => {
    let route: RouteRecordRaw | undefined

    beforeEach(() => {
      route = productRoutes.find((route: RouteRecordRaw) => route.path === '/pricing')
    })

    it('should define pricing route correctly', () => {
      expect(route).toBeDefined()
      expect(route?.name).toBe('Pricing')
      expect(route?.path).toBe('/pricing')
    })

    it('should have correct authentication requirements', () => {
      expect(route?.meta?.requiresAuth).toBe(false)
    })

    it('should use correct layout', () => {
      expect(route?.meta?.layout).toBe(WideLayout)
    })

    it('should have correct layout properties', () => {
      expect(route?.meta?.layoutProps).toBeDefined()
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true)
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true)
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true)
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(true)
    })

    it('should have props enabled', () => {
      expect(route?.props).toBe(true)
    })

    it('should load component lazily', () => {
      expect(route?.component).toBeDefined()
      if (route?.component) {
        expect(typeof route.component).toBe('function')
        const componentStr = route.component.toString()
        expect(componentStr).toContain('import')
      }
    })
  })

  describe('Route Collection', () => {
    it('should export an array of routes', () => {
      expect(Array.isArray(productRoutes)).toBe(true)
      expect(productRoutes.length).toBeGreaterThan(0)
    })

    it('should have valid route records', () => {
      productRoutes.forEach(route => {
        expect(route).toHaveProperty('path')
        expect(route).toHaveProperty('meta')
        expect(route.meta).toHaveProperty('layout')
        expect(route.meta).toHaveProperty('layoutProps')
      })
    })
  })
})
