<script setup lang="ts">
import DomainForm from '@/components/DomainForm.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { useRouter } from 'vue-router';

const router = useRouter();
const { isLoading, handleAddDomain, error } = useDomainsManager();

const onSubmit = async (domain: string) => {
  const result = await handleAddDomain(domain);
  if (result) {
    router.push({ name: 'AccountDomainVerify', params: { domain } });
  }
};
</script>

<template>
  <div class="">
    <h1 class="mb-6 text-3xl font-bold dark:text-white">
      Add your domain
    </h1>

    <ErrorDisplay v-if="error" :error="error" />

    <DomainForm
      :is-submitting="isLoading"
      @submit="onSubmit"
    />
  </div>
</template>
