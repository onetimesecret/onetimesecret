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

// Helper to map API record to User interface
function mapRecordToUser(record: any): User {
  return {
    id: record.objid || record.id,
    email: record.custid || record.email,
    created_at: record.created || record.created_at,
    status: record.status || 1,
    email_verified: record.email_verified || true,
    mfa_enabled: record.mfa_enabled || false,
    recovery_codes_count: record.recovery_codes_count || 0
  }
}

// Helper to check if auth response is valid
function isValidAuthResponse(data: any): boolean {
  return data.success && data.details?.authenticated && data.record
}

// Helper to clear authentication state
function clearAuthState(): void {
  state.value.user = null
  state.value.authenticated = false
}

export function useAuth() {
  const isAuthenticated = computed(() => state.value.authenticated)
  const user = computed(() => state.value.user)
  const loading = computed(() => state.value.loading)

  async function checkAuth(): Promise<void> {
    state.value.loading = true

    try {
      const response = await fetch('/auth/validate', {
        method: 'GET',
        credentials: 'include',
        headers: { 'Accept': 'application/json' }
      })

      if (response.ok) {
        const data = await response.json()
        if (isValidAuthResponse(data)) {
          state.value.user = mapRecordToUser(data.record)
          state.value.authenticated = true
        } else {
          clearAuthState()
        }
      } else {
        clearAuthState()
      }
    } catch (error) {
      console.error('Auth check failed:', error)
      clearAuthState()
    } finally {
      state.value.loading = false
    }
  }

  function login(): void {
    const authUrl = (import.meta as any).env.VITE_AUTH_URL || '/auth'
    const returnTo = encodeURIComponent(window.location.href)
    window.location.href = `${authUrl}/login?return_to=${returnTo}`
  }

  async function logout(): Promise<void> {
    try {
      const authUrl = (import.meta as any).env.VITE_AUTH_URL || '/auth'
      await fetch(`${authUrl}/logout`, { method: 'POST', credentials: 'include' })
      clearAuthState()
      window.location.href = '/'
    } catch (error) {
      console.error('Logout failed:', error)
    }
  }

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
