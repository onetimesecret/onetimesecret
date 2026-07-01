<!-- src/apps/secret/conceal/HomepageContent.vue -->

<script setup lang="ts">
  import HomepageTaglines from '@/apps/secret/components/conceal/HomepageTaglines.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { useLocalReceiptStore } from '@/shared/stores/localReceiptStore';
  import { storeToRefs } from 'pinia';

  const bootstrapStore = useBootstrapStore();
  const { authenticated, ui } = storeToRefs(bootstrapStore);

  // Resolve the active brand color so the CTA tracks the same source as the
  // logo (identityStore.primaryColor → --color-brand-500). Without this the
  // button falls back to SecretForm's neutral-blue default, so a branded
  // install shows a brand-colored logo above a neutral-blue button.
  const identityStore = useProductIdentity();
  const { primaryColor } = storeToRefs(identityStore);

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
      :with-recipient="false"
      :with-asterisk="true"
      :with-generate="true"
      :primary-color="primaryColor"
      :workspace-mode="localReceiptStore.workspaceMode" />

    <!-- Space divider -->
    <div class="mb-6"></div>

    <RecentSecretsTable />
  </div>
</template>
