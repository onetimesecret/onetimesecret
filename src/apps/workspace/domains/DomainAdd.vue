<!-- src/apps/workspace/domains/DomainAdd.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import DomainForm from '@/apps/workspace/components/domains/DomainForm.vue';
import ErrorDisplay from '@/shared/components/ui/ErrorDisplay.vue';
import { useDomainsManager } from '@/shared/composables/useDomainsManager';

const { t } = useI18n(); // auto-import

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
      {{ t('web.domains.add-your-domain') }}
    </h1>

    <ErrorDisplay v-if="error" :error="error" />

    <DomainForm
      :is-submitting="isLoading"
      @submit="handleAddDomain"
      @back="goBack" />
  </div>
</template>
