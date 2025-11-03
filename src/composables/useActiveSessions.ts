/**
 * Active sessions management composable
 * Handles fetching, removing, and managing user sessions
 */

import { ref, inject } from 'vue';
import type { AxiosInstance } from 'axios';
import {
  activeSessionsResponseSchema,
  removeSessionResponseSchema,
  isAuthError,
  type ActiveSessionsResponse,
  type RemoveSessionResponse,
} from '@/schemas/api/endpoints/auth';
import type { Session } from '@/types/auth';
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notificationsStore';

/* eslint-disable max-lines-per-function */
export function useActiveSessions() {
  const $api = inject('api') as AxiosInstance;
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();

  const sessions = ref<Session[]>([]);
  const isLoading = ref(false);
  const error = ref<string | null>(null);

  /**
   * Clears error state
   */
  function clearError() {
    error.value = null;
  }

  /**
   * Fetches all active sessions from backend
   *
   * @returns Array of sessions or empty array on error
   */
  async function fetchSessions(): Promise<Session[]> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.get<ActiveSessionsResponse>('/auth/active-sessions');
      const validated = activeSessionsResponseSchema.parse(response.data);

      // Convert null to undefined for TypeScript compatibility
      const mappedSessions = validated.sessions.map((session) => ({
        ...session,
        ip_address: session.ip_address ?? undefined,
        user_agent: session.user_agent ?? undefined,
      }));

      sessions.value = mappedSessions;
      return mappedSessions;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Failed to load sessions';
      sessions.value = [];
      return [];
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Removes a specific session by ID
   *
   * @param sessionId - ID of session to remove
   * @returns true if removal successful
   */
  async function removeSession(sessionId: string): Promise<boolean> {
    clearError();
    isLoading.value = true;

    try {
      const response = await $api.delete<RemoveSessionResponse>(
        `/auth/active-sessions/${sessionId}`,
        {
          data: {
            shrimp: csrfStore.shrimp,
          },
        }
      );

      const validated = removeSessionResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        error.value = validated.error;
        return false;
      }

      // Remove from local state
      sessions.value = sessions.value.filter((s) => s.id !== sessionId);

      notificationsStore.show('Session removed successfully', 'success', 'top');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Failed to remove session';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Removes all sessions except the current one
   *
   * @returns true if removal successful
   */
  async function removeAllOtherSessions(): Promise<boolean> {
    clearError();

    try {
      const response = await $api.post<RemoveSessionResponse>(
        '/auth/remove-all-active-sessions',
        {
          shrimp: csrfStore.shrimp,
        }
      );

      const validated = removeSessionResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        error.value = validated.error;
        return false;
      }

      // Keep only current session in local state
      sessions.value = sessions.value.filter((s) => s.is_current);

      notificationsStore.show('All other sessions have been logged out', 'success', 'top');
      return true;
    } catch (err: any) {
      error.value = err.response?.data?.error || 'Failed to remove sessions';
      return false;
    }
  }

  /**
   * Refreshes the sessions list
   * Alias for fetchSessions for clarity in usage
   */
  async function refreshSessions(): Promise<void> {
    await fetchSessions();
  }

  return {
    sessions,
    isLoading,
    error,
    fetchSessions,
    removeSession,
    removeAllOtherSessions,
    refreshSessions,
    clearError,
  };
}
