<template>
  <main>
    <div class="py-4 mb-16">
      <button @click="navigateToAddDomain">Add Domain</button> - <router-link to="/account/domains/add">Add Domain</router-link>
      <DomainsTable :shrimp="shrimp" :domains="domains" />
    </div>
  </main>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { CustomDomain } from '@/types/onetime';
import DomainsTable from '@/components/DomainsTable.vue';
import { useRouter } from 'vue-router';

const shrimp = ref(window.shrimp);

const isLoading = ref(false)
const error = ref('')
const domains = ref<CustomDomain[]>([])
  const router = useRouter();

const navigateToAddDomain = () => {
  router.push({ name: 'AccountDomainAdd' });
};


const fetchDomains = async () => {
  isLoading.value = true
  error.value = ''

  try {
    const response = await fetch('/api/v1/account/domains', {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      throw new Error('Failed to fetch domains')
    }

    const jsonData = await response.json()
    domains.value = jsonData.records || []
  } catch (err: unknown) {
    if (err instanceof Error) {
      error.value = err.message
    } else {
      console.error('An unexpected error occurred', err)
      error.value = 'An unexpected error occurred'
    }
  } finally {
    isLoading.value = false
  }
}

onMounted(() => {
  fetchDomains()
})

</script>
