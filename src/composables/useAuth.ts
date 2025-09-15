// src/composables/useAuth.ts

import { ref, computed } from 'vue'

interface User {
  id: string
  email: string
  created_at: string
  status: number
  email_verified: boolean
  mfa_enabled: boolean
  recovery_codes_count: number
}

interface AuthState {
  user: User | null
  authenticated: boolean
  loading: boolean
}

const state = ref<AuthState>({
  user: null,
  authenticated: false,
  loading: false
})

export function useAuth() {
  const isAuthenticated = computed(() => state.value.authenticated)
  const user = computed(() => state.value.user)
  const loading = computed(() => state.value.loading)

  // Check authentication status from server
  async function checkAuth(): Promise<void> {
    state.value.loading = true

    try {
      const response = await fetch('/auth/validate', {
        method: 'GET',
        credentials: 'include',
        headers: {
          'Accept': 'application/json'
        }
      })

      if (response.ok) {
        const data = await response.json()
        if (data.success && data.details?.authenticated && data.record) {
          // Map the record data to the expected User interface
          state.value.user = {
            id: data.record.objid || data.record.id,
            email: data.record.custid || data.record.email,
            created_at: data.record.created || data.record.created_at,
            status: data.record.status || 1,
            email_verified: data.record.email_verified || true,
            mfa_enabled: data.record.mfa_enabled || false,
            recovery_codes_count: data.record.recovery_codes_count || 0
          }
          state.value.authenticated = true
        } else {
          state.value.user = null
          state.value.authenticated = false
        }
      } else {
        state.value.user = null
        state.value.authenticated = false
      }
    } catch (error) {
      console.error('Auth check failed:', error)
      state.value.user = null
      state.value.authenticated = false
    } finally {
      state.value.loading = false
    }
  }

  // Redirect to login
  function login(): void {
    const authUrl = (import.meta as any).env.VITE_AUTH_URL || '/auth'
    const returnTo = encodeURIComponent(window.location.href)
    window.location.href = `${authUrl}/login?return_to=${returnTo}`
  }

  // Logout
  async function logout(): Promise<void> {
    try {
      const authUrl = (import.meta as any).env.VITE_AUTH_URL || '/auth'
      await fetch(`${authUrl}/logout`, {
        method: 'POST',
        credentials: 'include'
      })

      state.value.user = null
      state.value.authenticated = false

      // Redirect to home or login page
      window.location.href = '/'
    } catch (error) {
      console.error('Logout failed:', error)
    }
  }

  // Initialize auth state on app start
  function initialize(): Promise<void> {
    return checkAuth()
  }

  return {
    // State
    isAuthenticated,
    user,
    loading,

    // Actions
    checkAuth,
    login,
    logout,
    initialize
  }
}
