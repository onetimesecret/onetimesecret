<script setup lang="ts">
import SecretForm from '@/components/secrets/form/SecretForm.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';

</script>

<template>
  <div class="my-6">
    <DashboardTabNav />

    <SecretForm
                :withGenerate="true"
                :withRecipient="true" />
  </div>
</template>
