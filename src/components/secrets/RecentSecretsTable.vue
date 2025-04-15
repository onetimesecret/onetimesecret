<!-- src/components/secrets/RecentSecretsTable.vue -->

<script setup lang="ts">
  import SecretLinksTable from '@/components/secrets/SecretLinksTable.vue';
  import { useConcealedMetadataStore } from '@/stores/concealedMetadataStore';
  import { computed } from 'vue';


  const concealedMetadataStore = useConcealedMetadataStore();

  // Initialize the concealed metadata store if not already initialized
  if (!concealedMetadataStore.isInitialized) {
    concealedMetadataStore.init();
  }

  // Use the store's concealed messages
  const concealedMessages = computed(() => concealedMetadataStore.concealedMessages);
</script>

<template>
  <div>
    <template v-if="concealedMetadataStore.hasMessages">
      <SecretLinksTable :concealed-messages="concealedMessages" />
    </template>
  </div>
</template>
