<template>

  <div class="mb-4">
    <p class="text-base text-gray-600 dark:text-gray-400 mb-2">{{ $t('web.private.pretext') }}</p>

    <div class="relative">
      <input id="secreturi"
             class="w-full pr-10 px-3 py-2 bg-gray-100 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                         :value="`${metadata?.share_domain}/${metadata?.share_path}`"
             readonly />
      <button onclick="copyToClipboard('secreturi')"
              class="absolute inset-y-0 right-0 px-3 flex items-center text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              title="Copy to clipboard">
        <svg id="copyIcon"
             xmlns="http://www.w3.org/2000/svg"
             class="h-5 w-5"
             fill="none"
             viewBox="0 0 24 24"
             stroke="currentColor"
             width="20"
             height="20">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
        <svg id="checkIcon"
             xmlns="http://www.w3.org/2000/svg"
             class="h-5 w-5 text-green-500 hidden"
             fill="none"
             viewBox="0 0 24 24"
             stroke="currentColor"
             width="20"
             height="20">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7" />
        </svg>
      </button>
    </div>

    <!--{{#has_passphrase}}-->
    <p class="mt-2 font-bold text-gray-800 dark:text-gray-200">{{ $t('web.private.requires_passphrase') }}</p>
    <!--{{/has_passphrase}}-->
  </div>

</template>

<script setup lang="ts">
import { defineProps } from 'vue'
import { MetadataData, MetadataDetails } from '@/types/onetime.d'
// Was here: copyToClipboard

interface Props {
  metadata: MetadataData;
  details: MetadataDetails;
}

defineProps<Props>()

</script>
