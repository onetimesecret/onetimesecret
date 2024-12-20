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
  <div
    class="rounded-lg border-2 border-brand-100
              bg-brand-50/30 dark:border-brand-900 dark:bg-brand-950/30">
    <!-- Encryption Status (if needed) -->
    <div
      v-if="details.has_passphrase"
      class="flex items-center gap-2 border-b border-brand-100 px-4 py-2 dark:border-brand-900">
      <svg
        class="size-4 text-amber-500"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
        />
      </svg>
      <span class="text-sm font-medium text-amber-700 dark:text-amber-400">
        Protected with passphrase
      </span>
    </div>

    <!-- Share URL Section -->
    <div class="p-4">
      <label
        for="secreturi"
        class="block text-base font-medium text-gray-700 dark:text-gray-300">
        Secret Share Link
      </label>

      <div class="relative mt-2">
        <input
          id="secreturi"
          class="w-full rounded-lg border-2 border-gray-200
                 bg-white px-4 py-3 pr-12 font-mono text-sm
                 shadow-sm focus:border-brand-300 focus:outline-none focus:ring-2
                 focus:ring-brand-500/20 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-200"
          :value="metadata.share_url"
          readonly
        />
        <button
          @click="copySecretUrl"
          :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
          class="absolute inset-y-0 right-0 flex items-center justify-center px-3
                 text-gray-500 transition-colors hover:text-brand-600
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
    </div>
  </div>
</template>
