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

export function apiPlugin(apiInstance?: AxiosInstance) {
  const api = apiInstance || createApi();

  return (context: PiniaPluginContext) => {
    if (!context.store.$api) {
      context.store.$api = api;
    }
  };
}
