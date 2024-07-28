<template>
  <main class="container mx-auto px-4 py-8">
    <h1 class="text-3xl font-bold mb-6 dark:text-white">Add Domain</h1>
    <DomainForm :shrimp="shrimp" @domain-added="onDomainAdded" />
  </main>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import DomainForm from '@/components/DomainForm.vue';

const shrimp = ref(window.shrimp);
const router = useRouter();

const onDomainAdded = (domain: string) => {
  if (!domain) {
    throw new Error('Domain is undefined or empty');
  }
  try {
    router.push({ name: 'AccountDomainVerify', params: { domain } });
  } catch (error) {
    console.error('Navigation error:', error);
  }
};
</script>
