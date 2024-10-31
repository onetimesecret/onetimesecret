<template>
  <div class="min-h-screen flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8 bg-gray-50 dark:bg-gray-900">
    <div class="w-full max-w-md space-y-8">
      <!-- Loading State -->
      <div v-if="isLoading"
           class="flex justify-center items-center">
        <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-brand-500"></div>
      </div>

      <div v-else-if="record && details"
           class="bg-white dark:bg-gray-800 rounded-lg shadow-xl p-8">
        <!-- Secret Header -->
        <div class="flex items-center space-x-4 mb-8">
          <div class="h-12 w-12 rounded-full bg-brand-100 dark:bg-brand-900 flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg"
                 class="h-6 w-6 text-brand-600 dark:text-brand-400"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <div>
            <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
              {{ $t('web.shared.you_have_message') }}
            </h2>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {{ $t('web.COMMON.click_to_reveal') }}poop
            </p>
          </div>
        </div>

      </div>

      <!-- Unknown Secret -->
      <UnknownSecret v-else-if="!record" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { useFormSubmission } from '@/composables/useFormSubmission'
//import { useCsrfStore } from '@/stores/csrfStore'
import { AsyncDataResult, SecretData, SecretDataApiResponse, SecretDetails } from '@/types/onetime'
import UnknownSecret from '@/views/secrets/UnknownSecret.vue'
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

//const csrfStore = useCsrfStore();
const route = useRoute()

interface Props {
  secretKey: string
}

const props = defineProps<Props>()

const initialData = computed(() => route.meta.initialData as AsyncDataResult<SecretDataApiResponse>)

//const passphrase = ref('')
const finalRecord = ref<SecretData | null>(null)
const finalDetails = ref<SecretDetails | null>(null)

const {
  isSubmitting,
  //submitForm
} = useFormSubmission({
  url: `/api/v2/secret/${props.secretKey}`,
  successMessage: '',
  onSuccess: (data: SecretDataApiResponse) => {
    finalRecord.value = data.record
    finalDetails.value = data.details
  },
  onError: (data) => {
    console.debug('Error fetching secret:', data.message)
    throw new Error(data.message);
  },
})

// Compute the current state based on initial and final data
const record = computed(() => finalRecord.value || (initialData?.value.data?.record ?? null))
const details = computed(() => finalDetails.value || (initialData?.value.data?.details ?? null))
const isLoading = computed(() => isSubmitting.value)

// Watch for changes in the finalRecord and update the view accordingly
watch(finalRecord, (newValue) => {
  if (newValue) {
    console.log('Secret fetched successfully')
  }
})
</script>
