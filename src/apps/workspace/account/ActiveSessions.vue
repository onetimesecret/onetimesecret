<!-- src/apps/workspace/account/ActiveSessions.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useConfirmDialog } from '@vueuse/core';
  import SessionListItem from '@/apps/workspace/components/account/SessionListItem.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useActiveSessions } from '@/shared/composables/useActiveSessions';
  import { computed, onMounted, ref } from 'vue';

  const { t } = useI18n();
  const { sessions, isLoading, error, fetchSessions, removeSession, removeAllOtherSessions } =
    useActiveSessions();

  // Separate current and other sessions
  const currentSession = computed(() => sessions.value.find((s) => s.is_current));
  const otherSessions = computed(() => sessions.value.filter((s) => !s.is_current));

  // Confirmation dialog for removing all sessions
  const showRemoveAllConfirm = ref(false);

  // Confirmation dialog for individual session removal
  const {
    isRevealed: isRemoveOneRevealed,
    reveal: revealRemoveOne,
    confirm: confirmRemoveOne,
    cancel: cancelRemoveOne
  } = useConfirmDialog();

  const pendingRemoveSessionId = ref<string | null>(null);

  // Handle individual session removal
  const handleRemoveSession = async (sessionId: string) => {
    pendingRemoveSessionId.value = sessionId;
    const { isCanceled } = await revealRemoveOne();
    if (isCanceled) {
      pendingRemoveSessionId.value = null;
      return;
    }
    await removeSession(sessionId);
    pendingRemoveSessionId.value = null;
  };

  // Handle remove all sessions
  const handleRemoveAllSessions = async () => {
    showRemoveAllConfirm.value = false;
    await removeAllOtherSessions();
  };

  // Session count display
  const sessionCountDisplay = computed(() => {
    const count = sessions.value.length;
    return `${count} ${count === 1 ? t('web.auth.sessions.session_singular') : t('web.auth.sessions.session_plural')}`;
  });

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
          {{ t('web.auth.sessions.title') }} - {{ sessionCountDisplay }}
        </p>
      </div>

      <!-- Loading state -->
      <div
        v-if="isLoading"
        class="flex items-center justify-center py-12">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          class="mr-2 size-6 animate-spin text-gray-400"
          aria-hidden="true" />
        <span class="text-gray-600 dark:text-gray-400">{{ t('web.LABELS.loading') }}</span>
      </div>

      <!-- Error state -->
      <div
        v-else-if="error"
        class="rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
        role="alert">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>

      <!-- Sessions list -->
      <div
        v-else
        class="space-y-6">
        <!-- Current session -->
        <div v-if="currentSession">
          <h2 class="mb-3 text-lg font-semibold dark:text-white">
            {{ t('web.auth.sessions.current') }}
          </h2>
          <SessionListItem
            :session="currentSession"
            :is-current="true"
            @remove="handleRemoveSession" />
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
              class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:bg-red-700 dark:hover:bg-red-800">
              <OIcon
                collection="heroicons"
                name="arrow-right-on-rectangle-solid"
                class="mr-2 inline size-4"
                aria-hidden="true" />
              {{ t('web.auth.sessions.remove_all') }}
            </button>
          </div>
          <div class="space-y-3">
            <SessionListItem
              v-for="session in otherSessions"
              :key="session.id"
              :session="session"
              :is-current="false"
              @remove="handleRemoveSession" />
          </div>
        </div>

        <!-- No other sessions -->
        <div
          v-else-if="currentSession"
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800">
          <OIcon
            collection="heroicons"
            name="check-circle"
            class="mx-auto mb-2 size-8 text-green-500"
            aria-hidden="true" />
          <p class="text-gray-600 dark:text-gray-400">
            {{ t('web.auth.sessions.no_sessions') }}
          </p>
        </div>

        <!-- No sessions at all (shouldn't happen if authenticated) -->
        <div
          v-else
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800">
          <p class="text-gray-600 dark:text-gray-400">
            {{ t('web.auth.sessions.no_sessions') }}
          </p>
        </div>
      </div>

      <!-- Confirmation modal for removing all sessions -->
      <div
        v-if="showRemoveAllConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        @click.self="showRemoveAllConfirm = false">
        <div
          class="mx-4 max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
          role="dialog"
          aria-modal="true"
          aria-labelledby="remove-all-sessions-title">
          <div class="mb-4 flex items-center">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              class="mr-3 size-7 text-yellow-500"
              aria-hidden="true" />
            <h3
              id="remove-all-sessions-title"
              class="text-lg font-semibold dark:text-white">
              {{ t('web.auth.sessions.remove_all') }}
            </h3>
          </div>
          <p class="mb-6 text-gray-600 dark:text-gray-400">
            {{ t('web.auth.sessions.confirm_remove_all') }}
          </p>
          <div class="flex justify-end gap-3">
            <button
              @click="showRemoveAllConfirm = false"
              type="button"
              class="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
              {{ t('web.LABELS.cancel') }}
            </button>
            <button
              @click="handleRemoveAllSessions"
              type="button"
              class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2">
              {{ t('web.auth.sessions.remove_all') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Confirmation dialog for individual session removal -->
      <ConfirmDialog
        v-if="isRemoveOneRevealed"
        @confirm="confirmRemoveOne"
        @cancel="cancelRemoveOne"
        :title="t('web.auth.sessions.remove')"
        :message="t('web.auth.sessions.confirm_remove')"
        type="danger" />
    </div>
  </SettingsLayout>
</template>
