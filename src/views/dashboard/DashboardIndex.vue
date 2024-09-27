<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';

</script>

<template>
  <div>
    <DashboardTabNav />

    <SecretForm
                :withGenerate="true"
                :withRecipient="true" />
  </div>
</template>
