<script setup lang="ts">
import DomainForm from '@/components/DomainForm.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { ref } from 'vue';
import { useRouter } from 'vue-router';

const router = useRouter();
const { addDomain, isSubmitting } = useDomainsManager();
const isNavigating = ref(false);

const handleDomainSubmit = async (domain: string) => {
  const result = await addDomain(domain);
  if (result) {
    isNavigating.value = true;
    await router.replace({
      name: 'AccountDomainVerify',
      params: { domain }
    });
  }
};
</script>

<template>
  <div class="">
    <h1 class="mb-6 text-3xl font-bold dark:text-white">
      Add your domain
    </h1>
    <DomainForm
      :is-submitting="isSubmitting"
      @submit="handleDomainSubmit"
    />
    <p
      v-if="isNavigating"
      class="mt-4 text-gray-600 dark:text-gray-400">
      Navigating to verification page...
    </p>
  </div>
</template>
