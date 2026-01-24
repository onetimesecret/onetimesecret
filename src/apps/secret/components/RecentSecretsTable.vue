<!-- src/apps/secret/components/RecentSecretsTable.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import SecretLinksTable from '@/apps/secret/components/SecretLinksTable.vue';
  import { useRecentSecrets } from '@/shared/composables/useRecentSecrets';
  import { ref, onMounted, onUnmounted, computed } from 'vue';

  export interface Props {
    /** Whether to show the workspace mode toggle checkbox. Default true. */
    showWorkspaceModeToggle?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    showWorkspaceModeToggle: true,
  });

  const { t } = useI18n();
  const {
    records,
    hasRecords,
    workspaceMode,
    toggleWorkspaceMode,
    fetch,
    refreshStatuses,
    clear,
    updateMemo,
    isAuthenticated,
    currentScope,
    scopeLabel,
  } = useRecentSecrets();

  // Compute the description based on current scope
  const scopeDescription = computed(() => {
    if (!isAuthenticated.value || !currentScope.value || !scopeLabel.value) {
      return '';
    }

    const keyMap: Record<string, string> = {
      org: 'web.secrets.scope_org',
      domain: 'web.secrets.scope_domain',
    };

    const key = keyMap[currentScope.value];
    return key ? t(key, { name: scopeLabel.value }) : '';
  });

  const tableId = ref(`recent-secrets-${Math.random().toString(36).substring(2, 9)}`);

  // Throttle refresh to prevent excessive API calls on rapid tab switches
  const REFRESH_THROTTLE_MS = 5000;
  let lastRefreshTime = 0;

  // Refresh data when tab becomes visible (user returns from another tab)
  // Authenticated users: fetch fresh data from API
  // Guest users: refresh statuses from server to sync local storage
  // Throttled to prevent excessive requests on rapid tab switching
  // Errors are silently ignored - this is a background refresh, not user-initiated
  const handleVisibilityChange = async () => {
    if (document.visibilityState === 'visible') {
      const now = Date.now();
      if (now - lastRefreshTime < REFRESH_THROTTLE_MS) return;
      lastRefreshTime = now;

      try {
        if (isAuthenticated.value) {
          await fetch({ silent: true });
        } else {
          await refreshStatuses({ silent: true });
        }
      } catch {
        // Silently ignore errors on background refresh (e.g., server unavailable)
        // User didn't initiate this action, so don't show error toasts
      }
    }
  };

  // Fetch records on mount and set up visibility listener
  // For guest users, also refresh statuses from server to sync with actual state
  onMounted(async () => {
    await fetch();
    if (!isAuthenticated.value) {
      await refreshStatuses();
    }
    document.addEventListener('visibilitychange', handleVisibilityChange);
  });

  onUnmounted(() => {
    document.removeEventListener('visibilitychange', handleVisibilityChange);
  });

  // Method to dismiss/clear all recent secrets
  const dismissAllRecents = () => {
    clear();
  };

  // Method to update memo for a record
  const handleUpdateMemo = (id: string, memo: string) => {
    updateMemo(id, memo);
  };

  // Expose fetch for parent components to trigger refresh
  defineExpose({
    fetch,
  });
</script>

<template>
  <section
    aria-labelledby="recent-secrets-heading"
    class="pb-8">
    <div class="mb-4 flex items-center justify-between">
      <div>
        <h2
          id="recent-secrets-heading"
          class="text-lg font-medium text-gray-600 dark:text-gray-300">
          {{ t('web.COMMON.recent') }}
        </h2>
        <p
          v-if="scopeDescription"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ scopeDescription }}
        </p>
      </div>

      <div class="flex items-center gap-3">
        <!-- Workspace mode toggle (hideable via prop for dashboard chip control) -->
        <template v-if="props.showWorkspaceModeToggle">
          <label
            class="flex cursor-pointer items-center gap-2"
            :title="t('web.secrets.workspace_mode_description')">
            <input
              type="checkbox"
              :checked="workspaceMode"
              @change="toggleWorkspaceMode()"
              class="size-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700" />
            <span class="text-sm text-gray-600 dark:text-gray-300">
              {{ t('web.secrets.workspace_mode') }}
            </span>
          </label>

          <span
            v-if="hasRecords"
            class="text-gray-300 dark:text-gray-600"
            >|</span
          >
        </template>

        <span
          v-if="hasRecords"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.LABELS.items_count', { count: records.length }) }}
        </span>
        <button
          v-if="hasRecords"
          @click="dismissAllRecents"
          class="rounded p-1.5 text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
          :aria-label="t('web.LABELS.dismiss')"
          type="button">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden="true"
            focusable="false">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12" />
          </svg>
          <span class="sr-only">{{ t('web.LABELS.dismiss') }}</span>
        </button>
      </div>
    </div>

    <div
      :id="tableId"
      role="region"
      aria-live="polite">
      <SecretLinksTable
        :records="records"
        :aria-labelledby="'recent-secrets-heading'"
        @update:memo="handleUpdateMemo" />
    </div>
  </section>
</template>
