<!-- src/apps/secret/components/RecentSecretsTable.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import SecretLinksTable from '@/apps/secret/components/SecretLinksTable.vue';
import { useRecentSecrets } from '@/shared/composables/useRecentSecrets';
import type { ConcealedMessage } from '@/types/ui/concealed-message';
import { computed, ref, onMounted } from 'vue';

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
  clear,
} = useRecentSecrets();

const tableId = ref(`recent-secrets-${Math.random().toString(36).substring(2, 9)}`);

// Fetch records on mount
onMounted(() => {
  fetch();
});

// Extract ConcealedMessage from local records for SecretLinksTable compatibility
// SecretLinksTableRow requires the full ConcealedMessage structure
const concealedMessages = computed<ConcealedMessage[]>(() =>
  records.value
    .filter((record) => record.source === 'local')
    .map((record) => record.originalRecord as ConcealedMessage)
);

// Compute the items count
const itemsCount = computed(() => records.value.length);

// Method to dismiss/clear all recent secrets
const dismissAllRecents = () => {
  clear();
};
</script>

<template>
  <section aria-labelledby="recent-secrets-heading">
    <div
      v-if="hasRecords"
      class="mb-4 flex items-center justify-between">
      <div>
        <h2
          id="recent-secrets-heading"
          class="text-xl font-medium text-gray-700 dark:text-gray-200">
          {{ t('web.COMMON.recent') }}
        </h2>
        <p class="text-sm text-gray-500 dark:text-gray-400">
          Secrets created in this session.
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
              class="size-4 rounded border-gray-300 text-brand-600
                focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700" />
            <span class="text-sm text-gray-600 dark:text-gray-300">
              {{ t('web.secrets.workspace_mode') }}
            </span>
          </label>

          <span class="text-gray-300 dark:text-gray-600">|</span>
        </template>

        <span
          v-if="hasRecords"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.LABELS.items_count', { count: itemsCount }) }}
        </span>
        <button
          @click="dismissAllRecents"
          class="rounded p-1.5 text-gray-500 hover:bg-gray-100 hover:text-gray-700
            dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
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
        :concealed-messages="concealedMessages"
        :aria-labelledby="'recent-secrets-heading'" />
    </div>
  </section>
</template>
