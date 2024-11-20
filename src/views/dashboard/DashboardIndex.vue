
<template>
  <div class="min-h-[50vh]">
    <DashboardTabNav />

    <SecretForm
      :with-generate="true"
      :with-recipient="true"
    />
  </div>
</template>

<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import SecretForm from '@/components/secrets/form/SecretForm.vue';
</script>
