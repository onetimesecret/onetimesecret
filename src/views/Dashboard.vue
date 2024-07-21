<template>
  <main>

    <SecretForm :shrimp="shrimp" :show-generate="true" :with-recipient="true" />

  </main>
</template>

<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';

const shrimp = window.shrimp;

</script>
