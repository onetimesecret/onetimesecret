<template>
  <main class="container mx-auto px-4 py-8">
    <h1 class="text-3xl font-bold mb-6 dark:text-white">Add your domain</h1>
    <DomainForm :shrimp="shrimp" @domain-added="onDomainAdded" :disabled="isNavigating" />
    <p v-if="isNavigating" class="mt-4 text-gray-600 dark:text-gray-400">Navigating to verification page...</p>
  </main>
</template>

<script setup lang="ts">
import { nextTick, ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import DomainForm from '@/components/DomainForm.vue';

const shrimp = ref(window.shrimp);
const router = useRouter();
const isNavigating = ref(false);

onMounted(() => {
  console.log('AccountDomainAdd component mounted');
});

const onDomainAdded = async (domain: string) => {
  if (!domain) {
    throw new Error('Domain is undefined or empty');
  }
  isNavigating.value = true;
  try {
    console.info('Navigation to verify', domain);
    await router.replace({ name: 'AccountDomainVerify', params: { domain } });
    await nextTick();
  } catch (error) {
    console.error('Navigation error:', error);
    isNavigating.value = false;
    // Handle the error (e.g., show an error message to the user)
  }
};
</script>
