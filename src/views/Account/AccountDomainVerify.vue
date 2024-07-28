<template>
  <main class="container mx-auto px-4 py-8">
    <h1 class="text-3xl font-bold mb-6 dark:text-white">Verify Domain</h1>
    <VerifyDomainDetails v-if="domain" :domain="domain" />
    <p v-else class="text-gray-600 dark:text-gray-400">Loading domain information...</p>
  </main>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import VerifyDomainDetails from '@/components/VerifyDomainDetails.vue';
import { APIRecordResponse, CustomDomain } from '@/types/onetime';

const route = useRoute();
const domain = ref<CustomDomain | null>(null);

const fetchDomain = async (): Promise<void> => {
  const domainName: string = route.params.domain as string;
  try {
    const response: Response = await fetch(`/api/v1/account/domains/${domainName}`);
    if (!response.ok) {
      throw new Error('Failed to fetch domain information');
    }
    const data: APIRecordResponse = await response.json();
    domain.value = data.record as CustomDomain;
    console.log('data', data)
  } catch (error) {
    console.error('Error fetching domain:', error);
    // Handle error (e.g., show error message to user)
  }
};

onMounted(() => {
  fetchDomain();
});
</script>
