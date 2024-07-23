<template>
  <main>

    <SecretForm :shrimp="shrimp" :withGenerate="true" :withRecipient="true" />

  </main>
</template>

<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';

const shrimp = window.shrimp;

</script>
