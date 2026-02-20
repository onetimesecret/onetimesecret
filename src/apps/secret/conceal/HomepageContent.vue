<!-- src/apps/secret/conceal/HomepageContent.vue -->

<script setup lang="ts">
  import HomepageTaglines from '@/apps/secret/components/conceal/HomepageTaglines.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useLocalReceiptStore } from '@/shared/stores/localReceiptStore';
  import { storeToRefs } from 'pinia';

  const bootstrapStore = useBootstrapStore();
  const { authenticated, ui } = storeToRefs(bootstrapStore);

  const localReceiptStore = useLocalReceiptStore();
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-4">
    <HomepageTaglines
      v-if="!authenticated"
      class="mb-6" />

    <SecretForm
      v-if="ui?.enabled !== false"
      class="mb-10"
      :with-recipient="true"
      :with-asterisk="true"
      :with-generate="true"
      :workspace-mode="localReceiptStore.workspaceMode" />

    <!-- Space divider -->
    <div class="mb-6 "></div>

    <RecentSecretsTable />
  </div>
</template>
