<!-- src/views/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import RecentSecretsTable from '@/components/secrets/RecentSecretsTable.vue';
</script>

<template>

  <div class="container mx-auto min-w-[320px] max-w-2xl">
      <DashboardTabNav />

      <SecretForm
        class="mb-12"
        :with-generate="true"
        :with-recipient="true"
      />

      <!-- Visual divider -->
      <div class="border-t border-gray-200 dark:border-gray-700 my-6"></div>

      <RecentSecretsTable />
    </div>

</template>
