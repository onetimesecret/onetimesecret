<script setup lang="ts">
import DomainForm from '@/components/DomainForm.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';

const {
  isLoading,
  error,
  handleAddDomain,
  goBack
} = useDomainsManager();
</script>

<template>
  <div class="">
    <h1 class="mb-6 text-3xl font-bold dark:text-white">
      {{ $t('add-your-domain') }}
    </h1>

    <ErrorDisplay v-if="error" :error="error" />

    <DomainForm
      :is-submitting="isLoading"
      @submit="handleAddDomain"
      @back="goBack"
    />
  </div>
</template>
