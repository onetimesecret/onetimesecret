<template>
  <div class="">
    <h1 class="text-3xl font-bold mb-6 dark:text-white">Add your domain</h1>
    <DomainForm
      :is-submitting="isSubmitting"
      @submit="handleDomainSubmit"
    />
    <p v-if="isNavigating" class="mt-4 text-gray-600 dark:text-gray-400">
      Navigating to verification page...
    </p>
  </div>
</template>

<script setup lang="ts">
import DomainForm from '@/components/DomainForm.vue';
import { useDomainsStore } from '@/stores/domainsStore';
import { useNotificationsStore } from '@/stores/notifications';
import { nextTick, ref } from 'vue';
import { useRouter } from 'vue-router';

const router = useRouter();
const domainsStore = useDomainsStore();
const notifications = useNotificationsStore();

const isSubmitting = ref(false);
const isNavigating = ref(false);

const handleDomainSubmit = async (domain: string) => {
  if (!domain) {
    return notifications.show('Domain is required', 'error')
  }

  isSubmitting.value = true;

  try {
    await domainsStore.addDomain(domain);
    notifications.show(`Added domain ${domain}`, 'success');

    // Navigate to verification
    isNavigating.value = true;
    await router.replace({ name: 'AccountDomainVerify', params: { domain } });
    await nextTick();

  } catch (err) {
    console.log('blooop', err)
    const error = err instanceof Error
      ? err.message
      : 'Failed to add domain';
    notifications.show(error, 'error');

  } finally {
    isSubmitting.value = false;
  }
};
</script>
