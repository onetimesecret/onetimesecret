<template>
  <div class="mt-24">
    <div v-if="isLoading">Loading...</div>
    <div v-else-if="record && details"
         class="space-y-20">
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

      <!-- Secret confirmation form -->
      <div v-if="!details.show_secret">
        <div class="">
          <BasicFormAlerts :success="success"
                           :error="error" />

          <p v-if="details.verification && !details.has_passphrase"
             class="text-md text-gray-600 dark:text-gray-400">
            {{ $t('web.COMMON.click_to_verify') }}
          </p>
          <h2 v-if="details.has_passphrase"
              class="text-xl font-bold text-gray-800 dark:text-gray-200">
            {{ $t('web.shared.requires_passphrase') }}
          </h2>

          <form @submit.prevent="submitForm"
                class="space-y-4">
            <input name="shrimp"
                   type="hidden"
                   :value="csrfStore.shrimp" />
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
          <div class="text-right items-center mt-4">
            <p class="text-sm text-gray-500 dark:text-gray-400 italic">
              {{ $t('web.COMMON.careful_only_see_once') }}
            </p>
          </div>
        </div>

        <!-- Recipient onboarding  -->
        <div v-if="!record.verification">
          <SecretRecipientOnboardingContent />
        </div>
      </div>

      <!-- Display the secret -->
      <div v-else
           class="space-y-4">
        <h2 class="text-gray-600 dark:text-gray-400">{{ $t('web.shared.this_message_for_you') }}</h2>

        <SecretDisplayCase :secret="record"
                           :details="details" />
      </div>
    </div>

    <UnknownSecret v-else-if="!record"></UnknownSecret>

  </div>
</template>

<script setup lang="ts">
import { AsyncDataResult } from '@/api/secrets'
import BasicFormAlerts from '@/components/BasicFormAlerts.vue'
import SecretDisplayCase from '@/components/secrets/SecretDisplayCase.vue'
import SecretRecipientOnboardingContent from '@/components/secrets/SecretRecipientOnboardingContent.vue'
import { useFormSubmission } from '@/composables/useFormSubmission'
import { useCsrfStore } from '@/stores/csrfStore'
import { SecretData, SecretDataApiResponse, SecretDetails } from '@/types/onetime'
import UnknownSecret from '@/views/secrets/UnknownSecret.vue'
import { computed, ref, watch } from 'vue'

const csrfStore = useCsrfStore();

interface Props {
  secretKey: string
  initialData: AsyncDataResult<SecretDataApiResponse> | null
}

const props = defineProps<Props>()

console.log("record", props.initialData?.data?.record)
console.log("details", props.initialData?.data?.details)

const passphrase = ref('')
const finalRecord = ref<SecretData | null>(null)
const finalDetails = ref<SecretDetails | null>(null)

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
    finalRecord.value = data.record
    finalDetails.value = data.details
  },
  onError: (data) => {
    console.error('Error fetching secret:', data)
  },
})

// Compute the current state based on initial and final data
const record = computed(() => finalRecord.value || (props.initialData?.data?.record ?? null))
const details = computed(() => finalDetails.value || (props.initialData?.data?.details ?? null))
const isLoading = computed(() => isSubmitting.value)
const error = computed(() => submissionError.value)


// Watch for changes in the finalRecord and update the view accordingly
watch(finalRecord, (newValue) => {
  if (newValue) {
    console.log('Secret fetched successfully')
  }
})
</script>
