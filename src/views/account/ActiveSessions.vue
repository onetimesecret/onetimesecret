<script setup lang="ts">
import { onMounted, computed, ref } from 'vue';
import { useActiveSessions } from '@/composables/useActiveSessions';
import SessionListItem from '@/components/account/SessionListItem.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const { sessions, isLoading, error, fetchSessions, removeSession, removeAllOtherSessions } =
  useActiveSessions();

// Separate current and other sessions
const currentSession = computed(() => sessions.value.find((s) => s.is_current));
const otherSessions = computed(() => sessions.value.filter((s) => !s.is_current));

// Confirmation dialog state
const showRemoveAllConfirm = ref(false);

// Handle individual session removal
const handleRemoveSession = async (sessionId: string) => {
  const confirmed = window.confirm(t('web.auth.sessions.confirm-remove'));
  if (!confirmed) return;

  await removeSession(sessionId);
}

// Handle remove all sessions
const handleRemoveAllSessions = async () => {
  showRemoveAllConfirm.value = false;
  await removeAllOtherSessions();
}

onMounted(async () => {
  await fetchSessions();
});
</script>

<template>
  <SettingsLayout>
    <div>
      <div class="mb-6">
        <h1 class="text-3xl font-bold dark:text-white">
          {{ t('web.auth.sessions.title') }}
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          {{ t('web.auth.sessions.title') }} -
          {{ sessions.length }} {{ sessions.length === 1 ? 'session' : 'sessions' }}
        </p>
      </div>

      <!-- Loading state -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <i class="fas fa-spinner fa-spin mr-2 text-2xl text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">Loading sessions...</span>
      </div>

      <!-- Error state -->
      <div
        v-else-if="error"
        class="rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
        role="alert"
      >
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>

      <!-- Sessions list -->
      <div v-else class="space-y-6">
        <!-- Current session -->
        <div v-if="currentSession">
          <h2 class="mb-3 text-lg font-semibold dark:text-white">
            {{ t('web.auth.sessions.current') }}
          </h2>
          <SessionListItem
            :session="currentSession"
            :is-current="true"
            @remove="handleRemoveSession"
          />
        </div>

        <!-- Other sessions -->
        <div v-if="otherSessions.length > 0">
          <div class="mb-3 flex items-center justify-between">
            <h2 class="text-lg font-semibold dark:text-white">
              {{ t('web.auth.sessions.other') }}
            </h2>
            <button
              @click="showRemoveAllConfirm = true"
              type="button"
              class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:bg-red-700 dark:hover:bg-red-800"
            >
              <i class="fas fa-sign-out-alt mr-2"></i>
              {{ t('web.auth.sessions.remove-all') }}
            </button>
          </div>
          <div class="space-y-3">
            <SessionListItem
              v-for="session in otherSessions"
              :key="session.id"
              :session="session"
              :is-current="false"
              @remove="handleRemoveSession"
            />
          </div>
        </div>

        <!-- No other sessions -->
        <div
          v-else-if="currentSession"
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800"
        >
          <i class="fas fa-check-circle mb-2 text-3xl text-green-500"></i>
          <p class="text-gray-600 dark:text-gray-400">
            {{ t('web.auth.sessions.no-sessions') }}
          </p>
        </div>

        <!-- No sessions at all (shouldn't happen if authenticated) -->
        <div
          v-else
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800"
        >
          <p class="text-gray-600 dark:text-gray-400">No active sessions found.</p>
        </div>
      </div>

      <!-- Confirmation modal for removing all sessions -->
      <div
        v-if="showRemoveAllConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
        @click.self="showRemoveAllConfirm = false"
      >
        <div
          class="mx-4 max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
          role="dialog"
          aria-modal="true"
          :aria-labelledby="t('web.auth.sessions.remove-all')"
        >
          <div class="mb-4 flex items-center">
            <i class="fas fa-exclamation-triangle mr-3 text-2xl text-yellow-500"></i>
            <h3 class="text-lg font-semibold dark:text-white">
              {{ t('web.auth.sessions.remove-all') }}
            </h3>
          </div>
          <p class="mb-6 text-gray-600 dark:text-gray-400">
            {{ t('web.auth.sessions.confirm-remove-all') }}
          </p>
          <div class="flex justify-end gap-3">
            <button
              @click="showRemoveAllConfirm = false"
              type="button"
              class="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
            >
              Cancel
            </button>
            <button
              @click="handleRemoveAllSessions"
              type="button"
              class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
            >
              {{ t('web.auth.sessions.remove-all') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
