<script setup lang="ts">
import { useClipboard } from '@/composables/useClipboard'
import { Metadata, MetadataDetails } from '@/schemas/models'

interface Props {
  record: Metadata;
  details: MetadataDetails;
}

const props = defineProps<Props>()

const { isCopied, copyToClipboard } = useClipboard()

const copySecretUrl = () => {
  copyToClipboard(props.record?.share_url)
}
</script>

<template>
  <div class="overflow-hidden rounded-xl border-2 border-brand-100 bg-gradient-to-b from-brand-50/40 to-brand-50/20 shadow-sm dark:border-brand-900 dark:from-brand-950/40 dark:to-brand-950/20">
    <!-- Encryption Status -->
    <div
      v-if="details?.has_passphrase"
      class="flex items-center gap-2.5 border-b border-brand-100/50 bg-amber-50/50 px-4 py-2.5 dark:border-brand-900/50 dark:bg-amber-950/30">
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
    <div class="p-5">
      <label
        for="secreturi"
        class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
        Secret Share Link
      </label>

      <div class="group relative mt-1.5">
        <input
          id="secreturi"
          class="w-full rounded-lg border-2 border-gray-200 bg-white/80 px-4 py-3 pr-12
                      font-mono text-sm shadow-sm transition-colors
                      focus:border-brand-300 focus:bg-white focus:outline-none focus:ring-2
                      focus:ring-brand-500/20 dark:border-gray-800 dark:bg-gray-900/80
                      dark:text-gray-200 dark:focus:bg-gray-900"
          :value="record?.share_url"
          readonly
          aria-label="Secret sharing URL"
        />

        <button
          @click="copySecretUrl"
          :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
          class="absolute inset-y-0 right-0 flex items-center justify-center px-3.5
                       text-gray-400 transition-colors hover:text-brand-600
                       group-hover:text-gray-500 dark:text-gray-500
                       dark:hover:text-brand-400 dark:group-hover:text-gray-400"
          :aria-label="isCopied ? 'URL copied' : 'Copy URL to clipboard'">
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
            class="size-5 text-emerald-500"
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
