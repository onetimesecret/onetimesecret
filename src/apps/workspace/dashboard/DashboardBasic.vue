<!-- src/apps/workspace/dashboard/DashboardBasic.vue -->

<!-- Basic dashboard for free tier users -->

<script setup lang="ts">
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';
  import { computed, ref } from 'vue';

  const bootstrapStore = useBootstrapStore();
  const { cust } = storeToRefs(bootstrapStore);

  // Show beta features if enabled
  const isBetaEnabled = computed(() => cust.value?.feature_flags?.beta ?? false);

  // Recent secrets table ref for refreshing after creation
  const recentSecretsTableRef = ref<InstanceType<typeof RecentSecretsTable> | null>(null);

  // Refresh recent secrets table after a secret is created
  const handleSecretCreated = () => {
    recentSecretsTableRef.value?.fetch();
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true"
      @created="handleSecretCreated" />

    <RecentSecretsTable
      v-if="isBetaEnabled"
      ref="recentSecretsTableRef" />
  </div>
</template>
