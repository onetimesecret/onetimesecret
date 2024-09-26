
<template>
  <div class="container mx-auto p-14 max-w-2xl">
    <div v-if="isLoading">Loading...</div>
    <div v-else-if="error">Error: {{ error }}</div>
    <div v-else-if="record && details" class="space-y-8">
      <!-- Owner warning -->
      <div v-if="!details.verification && details.is_owner && !details.show_secret"
           class="bg-amber-50 border-l-4 border-amber-400 text-amber-700 p-4 mb-4 dark:bg-amber-900 dark:border-amber-500 dark:text-amber-100">
        <button type="button" class="float-right hover:text-amber-900 dark:hover:text-amber-50" @click="closeWarning">
          &times;
        </button>
        <strong class="font-medium">{{ $t('web.COMMON.warning') }}</strong>
        {{ $t('web.shared.you_created_this_secret') }}
      </div>

      <!-- Owner viewed secret -->
      <div v-if="!details.verification && details.is_owner && details.show_secret"
           class="bg-brand-50 border-l-4 border-brand-400 text-brand-700 p-4 mb-4 dark:bg-brand-900 dark:border-brand-500 dark:text-brand-100">
        <button type="button" class="float-right hover:text-brand-900 dark:hover:text-brand-50" @click="closeWarning">
          &times;
        </button>
        {{ $t('web.shared.viewed_own_secret') }}
      </div>

      <!-- Secret not yet shown -->
      <template v-if="!details.show_secret">
        <p v-if="details.verification && !details.has_passphrase" class="text-md text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.click_to_verify') }}
        </p>
        <h2 v-if="details.has_passphrase" class="text-xl font-bold text-gray-800 dark:text-gray-200">
          {{ $t('web.shared.requires_passphrase') }}
        </h2>

        <form @submit.prevent="submitForm" class="space-y-4">
          <input name="shrimp" type="hidden" :value="shrimp" />
          <input name="continue" type="hidden" value="true" />
          <input v-if="details.has_passphrase"
                 type="password"
                 v-model="passphrase"
                 class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                 :placeholder="$t('web.COMMON.enter_passphrase_here')" />
          <button type="submit"
                  class="w-full px-6 py-3 text-3xl font-semibold text-white bg-brand-500 rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800 transition duration-150 ease-in-out">
            {{ $t('web.COMMON.click_to_continue') }}
          </button>
        </form>

        <!-- Secret ready message -->
        <div v-if="!details.verification" class="bg-white dark:bg-gray-900">
          <!-- ... (rest of the "You've got (secret) mail" section) ... -->
        </div>
      </template>

      <!-- Secret shown -->
      <div v-else class="space-y-4">
        <h2 class="text-gray-600 dark:text-gray-400">{{ $t('web.shared.this_message_for_you') }}</h2>

        <div class="relative">
          <textarea class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white font-mono text-base leading-[1.2] tracking-wider bg-gray-100 dark:bg-gray-800 resize-none"
                    readonly
                    :rows="details.display_lines"
                    :value="details.secret_value"></textarea>
          <button @click="copyToClipboard"
                  class="absolute top-2 right-2 p-1.5 bg-gray-200 dark:bg-gray-600 rounded-md hover:bg-gray-300 dark:hover:bg-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-colors duration-200"
                  aria-label="Copy to clipboard">
            <!-- ... (SVG for copy icon) ... -->
          </button>
        </div>

        <p class="text-sm text-gray-500 dark:text-gray-400">
          ({{ $t('web.COMMON.careful_only_see_once') }})
        </p>

        <div v-if="details.is_truncated"
             class="bg-brandcomp-100 border-l-4 border-brandcomp-500 text-blue-700 p-4 text-sm dark:bg-blue-800 dark:text-blue-200">
          <button type="button" class="float-right" @click="closeTruncatedWarning">&times;</button>
          <strong>{{ $t('web.COMMON.warning') }}</strong>
          {{ $t('web.shared.secret_was_truncated') }} {{ record.original_size }}.
          <a v-if="!isAuthenticated" href="/signup" class="text-brand-500 hover:underline">
            {{ $t('web.COMMON.signup_for_more') }}
          </a>
        </div>
      </div>
    </div>
  </div>
  <UnknownSecret></UnknownSecret>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useFetchDataRecord } from '@/composables/useFetchData'
import { SecretData } from '@/types/onetime'
import UnknownSecret from '@/views/secrets/UnknownSecret.vue'

interface Props {
  secretKey: string
}

const props = defineProps<Props>()

const { record, details, isLoading, error, fetchData: fetchSecret } = useFetchDataRecord<SecretData>({
  url: `/api/v2/secret/${props.secretKey}`,
})

const passphrase = ref('')
const isAuthenticated = ref(false) // You might want to get this from a global state or auth service

onMounted(fetchSecret)

const submitForm = () => {
  // Implement form submission logic here
}

const copyToClipboard = () => {
  // Implement copy to clipboard logic here
}

const closeWarning = (event: Event) => {
  (event.target as HTMLElement).closest('.bg-amber-50, .bg-brand-50')?.remove()
}

const closeTruncatedWarning = (event: Event) => {
  (event.target as HTMLElement).closest('.bg-brandcomp-100')?.remove()
}
</script>
