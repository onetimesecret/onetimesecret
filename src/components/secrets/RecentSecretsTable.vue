<!-- src/components/secrets/RecentSecretsTable.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import HomepageLinksPlaceholder from '@/components/secrets/HomepageLinksPlaceholder.vue';
  import SecretLinksTable from '@/components/secrets/SecretLinksTable.vue';
  import { useConcealedMetadataStore } from '@/stores/concealedMetadataStore';


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
      <SecretLinksTable :concealedMessages="concealedMessages" />
    </template>
    <template v-else>
      <HomepageLinksPlaceholder
        title="No secrets yet"
        description="Create a secret above to get started." />
    </template>
  </div>
</template>
