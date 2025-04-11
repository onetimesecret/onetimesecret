<!-- src/views/Homepage.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import HomepageTaglines from '@/components/HomepageTaglines.vue';
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import { WindowService } from '@/services/window.service';
  import HomepageLinksPlaceholder from '@/components/secrets/HomepageLinksPlaceholder.vue';
  import SecretLinksTable from '@/components/secrets/SecretLinksTable.vue';
  import { useConcealedMetadataStore } from '@/stores/concealedMetadataStore';

  const windowProps = WindowService.getMultiple([
    'authenticated',
    'authentication',
    'plans_enabled',
  ]);

  const concealedMetadataStore = useConcealedMetadataStore();

  // Initialize the concealed metadata store if not already initialized
  if (!concealedMetadataStore.isInitialized) {
    concealedMetadataStore.init();
  }

  // Use the store's concealed messages
  const concealedMessages = computed(() => concealedMetadataStore.concealedMessages);
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-4">
    <HomepageTaglines
      v-if="!windowProps.authenticated"
      class="mb-6" />

    <SecretForm
      class="mb-12"
      :with-recipient="false"
      :with-asterisk="true"
      :with-generate="true" />

    <!-- Visual divider -->
    <div class="border-t border-gray-200 dark:border-gray-700 mb-6"></div>

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
  </div>
</template>
