<template>
  <main>

    <DomainForm :shrimp="shrimp" />

  </main>
</template>

<script setup lang="ts">
import DomainForm from '@/components/DomainForm.vue';

const shrimp = window.shrimp;

</script>
