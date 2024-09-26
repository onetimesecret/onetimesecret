<template>
  <div class="container mx-auto p-14 max-w-2xl">
    <div v-if="isLoading">Loading...</div>
    <!--<div v-else-if="error">Error: {{ error }}</div>-->
    <div v-else-if="record && details"
         class="space-y-8">
      <!-- Owner warning -->
      <div v-if="!details.verification && details.is_owner && !details.show_secret"
           class="bg-amber-50 border-l-4 border-amber-400 text-amber-700 p-4 mb-4 dark:bg-amber-900 dark:border-amber-500 dark:text-amber-100">
        <button type="button"
                class="float-right hover:text-amber-900 dark:hover:text-amber-50"
                @click="closeWarning">
          &times;
        </button>
        <strong class="font-medium">{{ $t('web.COMMON.warning') }}</strong>
        {{ $t('web.shared.you_created_this_secret') }}
      </div>

      <!-- Owner viewed secret -->
      <div v-if="!details.verification && details.is_owner && details.show_secret"
           class="bg-brand-50 border-l-4 border-brand-400 text-brand-700 p-4 mb-4 dark:bg-brand-900 dark:border-brand-500 dark:text-brand-100">
        <button type="button"
                class="float-right hover:text-brand-900 dark:hover:text-brand-50"
                @click="closeWarning">
          &times;
        </button>
        {{ $t('web.shared.viewed_own_secret') }}
      </div>

      <!-- Secret not yet shown -->
      <template v-if="!details.show_secret">
        <p v-if="details.verification && !details.has_passphrase"
           class="text-md text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.click_to_verify') }}
        </p>
        <h2 v-if="details.has_passphrase"
            class="text-xl font-bold text-gray-800 dark:text-gray-200">
          {{ $t('web.shared.requires_passphrase') }}
        </h2>

        <form @submit.prevent="submitForm" class="space-y-4">
          <input name="shrimp"
                 type="hidden"
                 :value="shrimp" />
          <input name="continue"
                 type="hidden"
                 value="true" />
          <input v-if="details.has_passphrase"
                 type="password"
                 v-model="passphrase"
                 name="passphrase"
                 class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                 :placeholder="$t('web.COMMON.enter_passphrase_here')" />
          <button type="submit"
                  :disabled="isSubmitting"
                  class="w-full px-6 py-3 text-3xl font-semibold text-white bg-brand-500 rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800 transition duration-150 ease-in-out">
            {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
          </button>
        </form>

        <BasicFormAlerts :success="success" :error="error" />


        <!-- Secret ready message -->
        <div v-if="!record.verification"
             class="bg-white dark:bg-gray-900">
          <!-- ... (rest of the "You've got (secret) mail" section) ... -->
           <div class="flex justify-between items-center mb-4">
              <h2 class="text-2xl font-bold text-gray-900 dark:text-white">{{$t('web.COMMON.secret_ready')}}</h2>
              <p class="text-sm text-gray-500 dark:text-gray-400 italic">
                {{$t('web.COMMON.careful_only_see_once')}}
              </p>
            </div>
        </div>
      </template>

      <!-- Secret shown -->
      <div v-else
           class="space-y-4">
        <h2 class="text-gray-600 dark:text-gray-400">{{ $t('web.shared.this_message_for_you') }}</h2>

        <SecretDisplayCase :secret="record" :details="details"/>
      </div>
    </div>
  </div>

  <UnknownSecret v-if="!record"></UnknownSecret>
</template>

<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue'
import { useFetchDataRecord } from '@/composables/useFetchData'
import { useFormSubmission } from '@/composables/useFormSubmission'
import { SecretData, SecretDataApiResponse, SecretDetails } from '@/types/onetime'
import { useWindowProps } from '@/composables/useWindowProps'
import UnknownSecret from '@/views/secrets/UnknownSecret.vue'
import SecretDisplayCase from '@/components/secrets/SecretDisplayCase.vue'
import BasicFormAlerts from '@/components/BasicFormAlerts.vue'

interface Props {
  secretKey: string
}

const props = defineProps<Props>()

const passphrase = ref('')
const {shrimp} = useWindowProps(['shrimp'])

const {
  record: initialRecord,
  details: initialDetails,
  isLoading: initialIsLoading,
  error: initialError,
  fetchData: fetchInitialSecret
} = useFetchDataRecord<SecretData>({
  url: `/api/v2/secret/${props.secretKey}`,
})

const finalRecord = ref<SecretData | null>(null)
const finalDetails = ref<SecretDetails | null>(null)

// This will get everything except for the actual secret value which is
// enough to present the confirmation form. The secret value will be fetched
// after the user clicks to continue.
onMounted(fetchInitialSecret)

const closeWarning = (event: Event) => {
  (event.target as HTMLElement).closest('.bg-amber-50, .bg-brand-50')?.remove()
}


const {
  isSubmitting,
  error: submissionError,
  success,
  submitForm
} = useFormSubmission({
  url: `/api/v2/secret/${props.secretKey}`,
  successMessage: '',
  onSuccess: (data: SecretDataApiResponse) => {
    // Update the finalRecord and finalDetails with the new data
    finalRecord.value = data.record
    finalDetails.value = data.details
  },
  onError: (data) => {
    console.error('Error fetching secret:', data)
  },
  // We don't handleShrimp here because the form can only be
  // submitted once so there's no need for a new shrimp.
})

// Compute the current state based on initial and final data
const record = computed(() => finalRecord.value || initialRecord.value)
const details = computed(() => finalDetails.value || initialDetails.value)
const isLoading = computed(() => initialIsLoading.value || isSubmitting.value)
const error = computed(() => submissionError.value || initialError.value)

// Watch for changes in the finalRecord and update the view accordingly
watch(finalRecord, (newValue) => {
  if (newValue) {
    // The secret has been successfully fetched, you can perform any additional actions here
    console.log('Secret fetched successfully')
  }
})
</script>
