<template>
  <div v-if="details?.is_destroyed"
       class="px-4 py-3 rounded relative border
       bg-red-100 border-red-400 text-red-700 dark:bg-red-800 dark:border-red-600 dark:text-red-100 mb-4">
    <strong class="font-bold">Cannot burn!</strong>
    <template>
      <span class="block sm:inline">
        <template v-if="details.is_received">
          The secret has already been viewed ({{ details.received_date }}).
        </template>
        <template v-if="details.is_burned">
          The secret has already been burned ({{ details.burned_date }}).
        </template>
      </span>
    </template>
    <a :href="record?.metadata_url"
       class="block w-full py-2 px-4 mt-2
         bg-gray-200 text-gray-700 rounded text-center hover:bg-gray-300
         transition duration-200 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600">Back</a>
  </div>

  <div v-else>
    <div class="mb-6">
      <span class="text-lg text-gray-600 dark:text-gray-400">{{ $t('web.COMMON.secret') }}:
        {{ record?.secret_shortkey }}</span>
      <h2 v-if="details?.has_passphrase"
          class="text-xl font-semibold mt-2 text-gray-800 dark:text-gray-200">
        {{ $t('web.page.requires_passphrase') }}
      </h2>
    </div>

    <form method="POST"
          class="space-y-4">
      <input type="hidden"
             name="shrimp"
             :value="shrimp" />
      <input type="hidden"
             name="continue"
             value="true" />
      <div v-if="details?.has_passphrase">
        <input type="password"
               name="passphrase"
               id="passField"
               class="w-full px-3 py-2 border rounded-md
               border-gray-300 bg-white dark:bg-gray-800 dark:border-gray-600 dark:text-gray-200
               focus:outline-none focus:ring-2 focus:ring-brand-500"
               placeholder="Enter the passphrase here" />
      </div>
      <button type="submit"
              class="w-full py-2 px-4 rounded-md
              bg-yellow-400 text-gray-800
              hover:bg-yellow-300 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800
              transition duration-200 flex items-center justify-center">
        <svg xmlns="http://www.w3.org/2000/svg"
             class="h-5 w-5 mr-2"
             viewBox="0 0 20 20"
             fill="currentColor"
             width="20"
             height="20">
          <path fill-rule="evenodd"
                d="M12.395 2.553a1 1 0 00-1.45-.385c-.345.23-.614.558-.822.88-.214.33-.403.713-.57 1.116-.334.804-.614 1.768-.84 2.734a31.365 31.365 0 00-.613 3.58 2.64 2.64 0 01-.945-1.067c-.328-.68-.398-1.534-.398-2.654A1 1 0 005.05 6.05 6.981 6.981 0 003 11a7 7 0 1011.95-4.95c-.592-.591-.98-.985-1.348-1.467-.363-.476-.724-1.063-1.207-2.03zM12.12 15.12A3 3 0 017 13s.879.5 2.5.5c0-1 .5-4 1.25-4.5.5 1 .786 1.293 1.371 1.879A2.99 2.99 0 0113 13a2.99 2.99 0 01-.879 2.121z"
                clip-rule="evenodd" />
        </svg>
        {{ $t('web.COMMON.word_confirm') }}: {{ $t('web.COMMON.burn_this_secret') }}
      </button>
      <a :href="record?.metadata_url"
         class="block w-full py-2 px-4 rounded text-center
         bg-gray-200 text-gray-700 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600
         transition duration-200">{{ $t('web.COMMON.word_cancel') }}</a>
      <hr class="border-gray-300 dark:border-gray-600" />
      <p class="text-md text-gray-600 dark:text-gray-400">
        {{ $t('web.COMMON.burn_this_secret_confirm_hint') }}
      </p>
    </form>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import type { MetadataData } from '@/types/onetime'
import { useFetchDataRecord } from '@/composables/useFetchData'

const shrimp = ref(window.shrimp);

// This prop is passed from vue-router b/c the route has `prop: true`.
interface Props {
  metadataKey: string
}

const props = defineProps<Props>()

const { record, details, fetchData: fetchMetadata } = useFetchDataRecord<MetadataData>({
  url: `/api/v2/private/${props.metadataKey}`,
})

onMounted(fetchMetadata)

</script>
