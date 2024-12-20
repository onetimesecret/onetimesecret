<script setup lang="ts">
import { useClipboard } from '@/composables/useClipboard'
import { Metadata, MetadataDetails } from '@/schemas/models'

interface Props {
  metadata: Metadata;
  details: MetadataDetails;
}

const props = defineProps<Props>()

const { isCopied, copyToClipboard } = useClipboard()

const copySecretUrl = () => {
  copyToClipboard(props.metadata.share_url)
}
</script>

<template>
  <div class="rounded-lg border border-gray-200 dark:border-gray-800">
    <div class="relative">
      <input
        id="secreturi"
        class="w-full rounded-lg border-0 bg-gray-50 px-4 py-3 pr-12 font-mono text-sm
               focus:outline-none focus:ring-2 focus:ring-brand-500/50
               dark:bg-gray-900 dark:text-gray-200"
        :value="metadata.share_url"
        readonly
      />
      <button
        @click="copySecretUrl"
        :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
        class="absolute inset-y-0 right-0 flex items-center justify-center w-12
               text-gray-500 hover:text-brand-600 transition-colors
               dark:text-gray-400 dark:hover:text-brand-400"
        aria-label="Copy to clipboard">
        <svg
          v-if="!isCopied"
          class="size-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
        <svg
          v-else
          class="size-5 text-green-500"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7"
          />
        </svg>
      </button>
    </div>

    <div
      v-if="details.has_passphrase"
      class="border-t border-gray-100 px-4 py-2 dark:border-gray-800">
      <p class="text-sm font-medium text-amber-600 dark:text-amber-400">
        {{ $t('web.private.requires_passphrase') }}
      </p>
    </div>
  </div>
</template>
