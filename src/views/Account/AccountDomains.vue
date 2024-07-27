<template>
  <main>

    <DomainsTable :domains="domains" />
    <DomainForm :shrimp="shrimp" />

  </main>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import DomainsTable from '@/components/DomainsTable.vue';
import DomainForm from '@/components/DomainForm.vue';
import { CustomDomain } from '@/types/onetime';

const shrimp = window.shrimp;

const isLoading = ref(false)
const error = ref('')
const domains = ref<CustomDomain[]>([])

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
