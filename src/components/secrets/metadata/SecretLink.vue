<script setup lang="ts">
import { useClipboard } from '@/composables/useClipboard'
import { MetadataData, MetadataDetails } from '@/types/core'

interface Props {
  metadata: MetadataData;
  details: MetadataDetails;
}

const props = defineProps<Props>()

const { isCopied, copyToClipboard } = useClipboard()

const copySecretUrl = () => {
  copyToClipboard(props.metadata.share_url)
}
</script>

<template>
  <div class="mb-4">
    <p class="mb-2 text-base text-gray-600 dark:text-gray-400">
      {{ $t('web.private.pretext') }}
    </p>

    <div class="relative">
      <input
        id="secreturi"
        class="w-full rounded-md border border-gray-300 bg-gray-100 px-3 py-2 pr-10 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        :value="metadata.share_url"
        readonly
      />
      <button
        @click="copySecretUrl"
        :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
        class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
        aria-label="Copy to clipboard">
        <svg
          v-if="!isCopied"
          xmlns="http://www.w3.org/2000/svg"
          class="size-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          width="20"
          height="20">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
        <svg
          v-else
          xmlns="http://www.w3.org/2000/svg"
          class="size-5 text-green-500"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          width="20"
          height="20">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7"
          />
        </svg>
      </button>
    </div>

    <p
      v-if="details.has_passphrase"
      class="mt-2 font-bold text-gray-800 dark:text-gray-200">
      {{ $t('web.private.requires_passphrase') }}
    </p>
  </div>
</template>
