<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';
import { useWindowProps } from '@/composables/useWindowProps';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';

const { shrimp } = useWindowProps(['shrimp']);


</script>

<template>

  <DashboardTabNav />

  <SecretForm :shrimp="shrimp"
              :withGenerate="true"
              :withRecipient="true" />

</template>
