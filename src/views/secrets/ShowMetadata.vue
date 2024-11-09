<template>
  <div>
    <DashboardTabNav />

    <BasicFormAlerts :error="error" />

    <div v-if="isLoading">Loading...</div>
    <div v-else-if="record && details">
      <SecretLink v-if="details.show_secret_link"
                  :metadata="record"
                  :details="details" />

      <h3 v-if="details.show_recipients"
          class="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">
        {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
      </h3>

      <MetadataDisplayCase :metadata="record"
                           :details="details" />

      <!-- These facts are about the actual secret -- not this metadata -->
      <p class="text-gray-600 dark:text-gray-400 mb-4">
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

      <BurnButtonForm :metadata="record"
                      :details="details" />

      <a href="/"
         class="block w-2/3 mx-auto px-4 py-2 mb-4 text-center rounded-md border-2 text-base font-medium bg-gray-200 text-gray-800 border-gray-300 dark:bg-gray-700 dark:text-gray-200 dark:border-gray-800 hover:bg-gray-100 hover:border-grey-200 dark:hover:bg-gray-600 dark:hover:border-gray-600">Create
        another secret</a>

      <MetadataFAQ :metadata="record"
                   :details="details" />
    </div>
  </div>
</template>

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue'
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue'
import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue'
import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue'
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue'
import SecretLink from '@/components/secrets/metadata/SecretLink.vue'
import { useFetchDataRecord } from '@/composables/useFetchData'
import { MetadataData } from '@/types'
import { onMounted } from 'vue'

// This prop is passed from vue-router b/c the route has `prop: true`.
interface Props {
  metadataKey: string
}

const props = defineProps<Props>()

const { record, details, isLoading, error, fetchData: fetchMetadata } = useFetchDataRecord<MetadataData>({
  url: `/api/v2/private/${props.metadataKey}`,
})

onMounted(fetchMetadata)
</script>
