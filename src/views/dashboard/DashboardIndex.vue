
<template>
  <div class="min-h-[50vh]">
    <DashboardTabNav />

    <SecretForm
      :withGenerate="true"
      :withRecipient="true"
    />
  </div>
</template>

<script setup lang="ts">
import SecretForm from '@/components/secrets/form/SecretForm.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
</script>
