import { describe, it, expect } from 'vitest'
import { RouteRecordRaw } from 'vue-router'
import accountRoutes from '@/router/account.routes'

describe('Account Routes', () => {
  describe('Account Route', () => {
    it('should define account route correctly', () => {
      const route = accountRoutes.find((route: RouteRecordRaw) => route.path === '/account')
      expect(route).toBeDefined()
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(route?.components?.default).toBeInstanceOf(Function)
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })

  describe('Account Domain Verify Route', () => {
    it('should define account domain verify route correctly', () => {
      const route = accountRoutes.find((route: RouteRecordRaw) => route.path === '/account/domains/:domain/verify')
      expect(route).toBeDefined()
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(route?.components?.default).toBeInstanceOf(Function)
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })

  describe('Account Domain Add Route', () => {
    it('should define account domain add route correctly', () => {
      const route = accountRoutes.find((route: RouteRecordRaw) => route.path === '/account/domains/add')
      expect(route).toBeDefined()
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(false)
      expect(route?.components?.default).toBeInstanceOf(Function)
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })

  describe('Colonel Route', () => {
    it('should define colonel route correctly', () => {
      const route = accountRoutes.find((route: RouteRecordRaw) => route.path === '/colonel')
      expect(route).toBeDefined()
      expect(route?.meta?.isAdmin).toBe(true)
      expect(route?.meta?.requiresAuth).toBe(true)
      expect(route?.components?.default).toBeInstanceOf(Function)
      expect(route?.components?.header).toBeDefined()
      expect(route?.components?.footer).toBeDefined()
    })
  })
})
