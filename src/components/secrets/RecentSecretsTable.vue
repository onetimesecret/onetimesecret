<!-- src/components/secrets/RecentSecretsTable.vue -->

<script setup lang="ts">
import SecretLinksTable from '@/components/secrets/SecretLinksTable.vue';
import { useConcealedMetadataStore } from '@/stores/concealedMetadataStore';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const concealedMetadataStore = useConcealedMetadataStore();
const tableId = ref(`recent-secrets-${Math.random().toString(36).substring(2, 9)}`);

// Initialize the concealed metadata store if not already initialized
if (!concealedMetadataStore.isInitialized) {
  concealedMetadataStore.init();
}

// Use the store's concealed messages
const concealedMessages = computed(() => concealedMetadataStore.concealedMessages);

// Compute the items count
const itemsCount = computed(() => concealedMessages.value.length);

// Method to dismiss/clear all recent secrets
const dismissAllRecents = () => {
  concealedMetadataStore.clearMessages();
};
</script>

<template>
  <section aria-labelledby="recent-secrets-heading">
    <div
      v-if="concealedMetadataStore.hasMessages"
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
        <span
          v-if="concealedMetadataStore.hasMessages"
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
