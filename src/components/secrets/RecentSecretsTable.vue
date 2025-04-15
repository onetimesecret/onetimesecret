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
</script>

<template>
  <section aria-labelledby="recent-secrets-heading">
    <div class="mb-4 flex items-center justify-between">
      <h2
        id="recent-secrets-heading"
        class="text-xl font-medium text-gray-700 dark:text-gray-200">
        {{ $t('web.COMMON.recent') }}
      </h2>

      <span
        v-if="concealedMetadataStore.hasMessages"
        class="text-sm text-gray-500 dark:text-gray-400">
        {{ $t('web.LABELS.items_count', { count: itemsCount }) }}
      </span>
    </div>

    <div
      v-if="concealedMetadataStore.hasMessages"
      :id="tableId"
      role="region"
      aria-live="polite">
      <SecretLinksTable
        :concealed-messages="concealedMessages"
        :aria-labelledby="'recent-secrets-heading'"
      />
    </div>

    <p
      v-else
      class="py-4 text-center text-gray-600 dark:text-gray-400"
      aria-live="polite">
      {{ t('web.secrets.no_recent_secrets') }}
    </p>
  </section>
</template>
