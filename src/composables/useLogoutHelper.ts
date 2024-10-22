import { useAuthStore } from '@/stores/authStore'
import { useLanguageStore } from '@/stores/languageStore'
import { useCsrfStore } from '@/stores/csrfStore'

export function useLogoutHelper() {
  const authStore = useAuthStore();
  const languageStore = useLanguageStore();
  const csrfStore = useCsrfStore();

  const deleteCookie = (name: string) => {
    console.debug('Deleting cookie:', name);
    document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;`;
  }

  return () => {

    // Reset all stores
    /**
     * Clears authentication state and storage.
     *
     * This method resets the store state to its initial values using `this.$reset()`.
     * It also clears session storage and stops any ongoing authentication checks.
     * This is typically used during logout to ensure that all user-specific data
     * is cleared and the store is returned to its default state.
     */
    authStore.$reset();
    languageStore.$reset();
    csrfStore.$reset();

    window.cust = null;
    window.authenticated = false;

    deleteCookie('sess');
    deleteCookie('locale');

    // Stop any ongoing auth checks
    authStore.stopAuthCheck()

    // Clear all session storage;
    sessionStorage.clear();

    console.debug('Goodnight Irene');
  }
}
