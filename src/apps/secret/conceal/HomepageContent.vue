<!-- src/apps/secret/conceal/HomepageContent.vue -->

<script setup lang="ts">
  import HomepageTaglines from '@/apps/secret/components/conceal/HomepageTaglines.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import { WindowService } from '@/services/window.service';
  import { useConcealedMetadataStore } from '@/shared/stores/concealedMetadataStore';
  import { computed } from 'vue';

  const windowProps = WindowService.getMultiple([
    'authenticated',
    'authentication',
    'billing_enabled',
    'ui',
  ]);

  const concealedMetadataStore = useConcealedMetadataStore();
  const hasRecentSecrets = computed(() => concealedMetadataStore.hasMessages);
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-4">
    <HomepageTaglines
      v-if="!windowProps.authenticated"
      class="mb-6" />

    <SecretForm
      v-if="windowProps.ui?.enabled !== false"
      class="mb-12"
      :with-recipient="false"
      :with-asterisk="true"
      :with-generate="true"
      :workspace-mode="concealedMetadataStore.workspaceMode" />

    <!-- Space divider -->
    <div class="mb-6 "></div>

    <RecentSecretsTable
      v-if="hasRecentSecrets" />
  </div>
</template>
