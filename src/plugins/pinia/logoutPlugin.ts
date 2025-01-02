import { useAuthStore } from '@/stores/authStore';
import { useCsrfStore } from '@/stores/csrfStore';
import { useLanguageStore } from '@/stores/languageStore';
import { PiniaPluginContext } from 'pinia';

// NOTE: For SSR, wrap document calls in a “process.client” or environment check.

export function logoutPlugin(context: PiniaPluginContext) {
  const deleteCookie = (name: string) => {
    console.debug('Deleting cookie:', name);
    document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;`;
  };

  // Add $logout to the store type
  if (!context.store.$logout) {
    /**
     * Clears authentication state and storage.
     *
     * This method resets the store state to its initial values using `this.$reset()`.
     * It also clears session storage and stops any ongoing authentication checks.
     * This is typically used during logout to ensure that all user-specific data
     * is cleared and the store is returned to its default state.
     */
    context.store.$logout = function () {
      const authStore = useAuthStore();
      const languageStore = useLanguageStore();
      const csrfStore = useCsrfStore();

      // Reset all stores
      authStore.$reset();
      languageStore.$reset();
      csrfStore.$reset();

      // Sync window state
      window.cust = null;
      window.authenticated = false;

      deleteCookie('sess');
      deleteCookie('locale');

      // Stop any ongoing auth checks
      authStore.$stopAuthCheck();
      // Clear all session storage;
      sessionStorage.clear();
      // Remove any and all lingering store state
      context.pinia.state.value = {};
    };
  }
}

/**
// Alternate implementation using store state
if (!context.store.$logout) {
  context.store.$logout = function () {
    // Get all stores and reset them
    const stores = Array.from(context.pinia.state.value).map(([id]) =>
      context.pinia._s.get(id)
    ).filter(Boolean);

    // Reset all stores
    stores.forEach(store => {
      if (typeof store.$reset === 'function') {
        store.$reset();
      }
    });

    // Clear cookies
    const COOKIES_TO_CLEAR = ['sess', 'locale'];
    COOKIES_TO_CLEAR.forEach(deleteCookie);

    // Clear browser storage
    sessionStorage.clear();

    // Reset window state
    if ('cust' in window) window.cust = null;
    if ('authenticated' in window) window.authenticated = false;

    // Special handling for auth store if it exists
    const authStore = context.pinia._s.get('auth');
    if (authStore && '$stopAuthCheck' in authStore) {
      authStore.$stopAuthCheck();
    }

    // Clear all Pinia state
    context.pinia.state.value = {};
  };
}

// Or go event based
export const LOGOUT_EVENTS = {
  BEFORE_LOGOUT: 'before-logout',
  AFTER_LOGOUT: 'after-logout',
  LOGOUT_ERROR: 'logout-error'
} as const;

export function logoutPlugin({ emitter }: { emitter?: EventEmitter } = {}) {
  return ({ store }: PiniaPluginContext) => {
    if (!store.$logout) {
      store.$logout = async function() {
        try {
          emitter?.emit(LOGOUT_EVENTS.BEFORE_LOGOUT);
          // Logout logic
          emitter?.emit(LOGOUT_EVENTS.AFTER_LOGOUT);
        } catch (error) {
          emitter?.emit(LOGOUT_EVENTS.LOGOUT_ERROR, error);
          throw error;
        }
      };
    }
  };
}
*/
