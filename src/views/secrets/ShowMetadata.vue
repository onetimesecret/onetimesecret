<template>
  <div>
    <DashboardTabNav />

    <div v-if="isLoading">Loading...</div>
    <div v-else-if="error">Error: {{ error }}</div>
    <div v-else-if="record && details">
      <!-- if show_secret_link -->
      <SecretLink v-if="details.show_secret_link" :metadata="record" :details="details" />

      <!-- if show_recipients -->
      <h3 v-if="details.show_recipients" class="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">
        {{$t('web.COMMON.sent_to')}} {{record.recipients}}
      </h3>

      <!-- if show_secret -->
      <DisplayCase v-if="details.show_secret" :metadata="record" :details="details" ></DisplayCase>

      <!-- else -->
      <div v-else class="mb-4">
        <p class="mb-2 text-gray-600 dark:text-gray-400">
          {{$t('web.COMMON.secret')}} ({{record.secret_shortkey}}):
        </p>
        <input
          class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
          value="*******************"
          disabled />
      </div>

      <p class="text-gray-600 dark:text-gray-400 mb-4">
        <template v-if="details.is_received">
          <em>{{$t('web.COMMON.received')}} {{details.received_date}}.</em>
          <span class="text-sm text-gray-500 dark:text-gray-400">({{details.received_date_utc}})</span>
        </template>
        <template v-else-if="details.is_burned">
          <em>{{$t('web.COMMON.burned')}} {{details.burned_date}}.</em>
          <span class="text-sm text-gray-500 dark:text-gray-400">({{details.burned_date_utc}})</span>
        </template>
        <template v-else-if="!details.is_destroyed">
          <strong>{{$t('web.COMMON.expires_in')}} {{record.expiration_stamp}}</strong>.
          <span class="text-sm text-gray-500 dark:text-gray-400">({{record.created_date_utc}})</span>
        </template>
      </p>

      <MetadataFAQ />
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useFetchDataRecord } from '@/composables/useFetchData'
import SecretLink from '@/components/secrets/metadata/SecretLink.vue'
import DisplayCase from '@/components/secrets/DisplayCase.vue'
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue'
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue'
import { MetadataData } from '@/types/onetime'

interface Props {
  metadataKey: string
}

const props = defineProps<Props>()

const { record, details, isLoading, error, fetchData: fetchMetadata } = useFetchDataRecord<MetadataData>({
  url: `/api/v2/private/${props.metadataKey}`,
})

onMounted(fetchMetadata)
</script>
