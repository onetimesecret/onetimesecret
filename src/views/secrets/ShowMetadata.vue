<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue';
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';
import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
import { isMetadataDetails } from '@/schemas/models/metadata';
import { useMetadataStore } from '@/stores/metadataStore';
import { AsyncDataResult, MetadataRecordApiResponse } from '@/types/api/responses';
import { storeToRefs } from 'pinia';
import { computed, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const store = useMetadataStore();

// Get initial data from route resolver
const initialData = computed(() => route.meta.initialData as AsyncDataResult<MetadataRecordApiResponse>);

// Set up reactive refs to store state
const { currentRecord: record, details, isLoading, error } = storeToRefs(store);

// Initialize from route resolver data
if (initialData.value?.data) {
  store.setData(initialData.value.data);
}
// Clean up on unmount
onUnmounted(() => {
  store.abortPendingRequests();
});
</script>

<template>
  <div>
    <DashboardTabNav />
    <BasicFormAlerts :error="error" />

    <div v-if="isLoading">
      Loading...
    </div>
    <div v-else-if="record && details">
      <template v-if="isMetadataDetails(details)">
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
          <template v-if="details.is_received && record.received">
            <em>{{ $t('web.COMMON.received') }} {{ record.natural_expiration }}. </em>
            <span v-if="record.received" class="text-sm text-gray-500 dark:text-gray-400">
              ({{ record.received }})
            </span>
          </template>
          <template v-else-if="details.is_burned ">
            <em>{{ $t('web.COMMON.burned') }} {{ record.natural_expiration }}. </em>
            <span v-if="record.burned" class="text-sm text-gray-500 dark:text-gray-400">
              ({{ record.burned }})
            </span>
          </template>
          <template v-else-if="!details.is_destroyed">
            <strong>{{ $t('web.COMMON.expires_in') }} {{ record.natural_expiration }}. </strong>
            <span class="text-sm text-gray-500 dark:text-gray-400">
              ({{ record.expiration }})
            </span>
          </template>
        </p>

        <BurnButtonForm
          :metadata="record"
          :details="details"
        />

        <hr class="mx-auto my-4 w-1/4 border-gray-200 dark:border-gray-600" />

        <a
          href="/"
          class="
            mx-auto
            mb-24
            mt-12
            block
            w-2/3
            rounded-md
            border-2
            border-gray-300
            bg-gray-200
            px-4
            py-2
            text-center
            text-base
            font-medium
            text-gray-800
            hover:border-gray-200
            hover:bg-gray-100
            dark:border-gray-800
            dark:bg-gray-700
            dark:text-gray-200
            dark:hover:border-gray-600
            dark:hover:bg-gray-600
          ">
          Create another secret
        </a>

        <MetadataFAQ
          :metadata="record"
          :details="details"
        />
      </template>
    </div>
  </div>
</template>
