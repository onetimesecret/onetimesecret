
<template>
  <div>
    <DashboardTabNav />
    <BasicFormAlerts :error="error" />

    <div v-if="isLoading">
      Loading...
    </div>
    <div v-else-if="record && details">
      <SecretLink
        v-if="details.show_secret_link"
        :metadata="record"
        :details="details"
      />

      <h3
        v-if="details.show_recipients"
        class="mb-4 text-lg font-semibold text-gray-800 dark:text-gray-200">
        {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
      </h3>

      <MetadataDisplayCase
        :metadata="record"
        :details="details"
      />

      <!-- These facts are about the actual secret -- not this metadata -->
      <p class="mb-4 text-gray-600 dark:text-gray-400">
        <template v-if="details.is_received">
          <em>{{ $t('web.COMMON.received') }} {{ details.received_date }}. </em>
          <span class="text-sm text-gray-500 dark:text-gray-400">({{ details.received_date_utc }})</span>
        </template>
        <template v-else-if="details.is_burned">
          <em>{{ $t('web.COMMON.burned') }} {{ details.burned_date }}. </em>
          <span class="text-sm text-gray-500 dark:text-gray-400">({{ details.burned_date_utc }})</span>
        </template>
        <template v-else-if="!details.is_destroyed">
          <strong>{{ $t('web.COMMON.expires_in') }} {{ record.expiration_stamp }}. </strong>
          <span class="text-sm text-gray-500 dark:text-gray-400">({{ record.created_date_utc }})</span>
        </template>
      </p>

      <BurnButtonForm
        :metadata="record"
        :details="details"
      />

      <a
        href="/"
        class="hover:border-grey-200 mx-auto mb-4 block w-2/3 rounded-md border-2 border-gray-300 bg-gray-200 px-4 py-2 text-center text-base font-medium text-gray-800 hover:bg-gray-100 dark:border-gray-800 dark:bg-gray-700 dark:text-gray-200 dark:hover:border-gray-600 dark:hover:bg-gray-600">Create
        another secret</a>

      <MetadataFAQ
        :metadata="record"
        :details="details"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue';
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';
import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
import { useMetadataStore } from '@/stores/metadataStore';
import { AsyncDataResult, MetadataDataApiResponse } from '@/types/api/responses';
import { storeToRefs } from 'pinia';
import { computed, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const store = useMetadataStore();

// Get initial data from route resolver
const initialData = computed(() => route.meta.initialData as AsyncDataResult<MetadataDataApiResponse>);

// Set up reactive refs to store state
const { currentRecord: record, details, isLoading, error } = storeToRefs(store);

// Initialize from route resolver data
if (initialData.value?.data) {
  record.value = initialData.value.data.record;
  details.value = initialData.value.data.details;
}

// Clean up on unmount
onUnmounted(() => {
  store.abortPendingRequests();
});
</script>
