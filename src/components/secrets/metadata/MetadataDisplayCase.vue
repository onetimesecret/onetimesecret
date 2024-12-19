<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { computed } from 'vue';

interface ExtendedMetadataDetails extends MetadataDetails {
  is_truncated?: boolean;
}

interface Props {
  metadata: Metadata;
  details: ExtendedMetadataDetails;
}

const props = defineProps<Props>();

// Core state computeds for clear state management
const isUnread = computed(() => props.details.show_secret)
const isViewable = computed(() => isUnread.value && props.details.can_decrypt)
const isBurned = computed(() => props.details.is_burned)

// Display helpers
const getStatusColor = computed(() => {
  if (isViewable.value) return 'emerald'
  if (isBurned.value) return 'red'
  return 'gray'
})
</script>

<template>
  <div>
    <!-- Common Header -->
    <div class="mb-4">
      <h2 class="flex items-center gap-2 font-mono text-lg text-gray-500 dark:text-gray-400">
        <span>Secret</span>
        <code
          class="rounded bg-gray-100 px-2 py-0.5
          font-semibold text-brand-600 dark:bg-gray-800 dark:text-brand-400">
          {{ metadata.secret_shortkey }}
        </code>
      </h2>
    </div>

    <!-- Dynamic Content Section -->
    <div :class="`rounded-md p-4 bg-${getStatusColor}-50 dark:bg-${getStatusColor}-950/30`">
      <!-- Viewable State -->
      <template v-if="isViewable">
        <div class="mb-3 flex items-center gap-2">
          <svg
            class="size-5 text-emerald-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 10V3L4 14h7v7l9-11h-7z"
            />
          </svg>
          <p class="text-sm font-medium text-emerald-700 dark:text-emerald-300">
            New secret created successfully!
          </p>
        </div>

        <div class="relative">
          <textarea
            class="w-full resize-none rounded-md border-2 border-emerald-300
                         bg-emerald-50/50 px-3 py-2 font-mono text-base leading-[1.2]
                         tracking-wider shadow-sm focus:outline-none focus:ring-2
                         focus:ring-brand-500 dark:border-emerald-800
                         dark:bg-emerald-950/30 dark:text-white"
            readonly
            :value="details.secret_value"
            :rows="details.display_lines || 3"></textarea>
          <div class="absolute right-2 top-2">
            <div class="size-2 rounded-full bg-emerald-400 dark:bg-emerald-500"></div>
          </div>
        </div>

        <span class="mt-2 block text-sm font-medium text-emerald-600 dark:text-emerald-400">
          ({{ $t('web.private.only_see_once') }})
        </span>
      </template>

      <!-- Burned State -->
      <template v-else-if="isBurned">
        <div class="flex items-center gap-2">
          <svg
            class="size-5 text-red-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
            />
          </svg>
          <p class="text-sm font-medium text-red-500 dark:text-red-400">
            This secret was permanently deleted before it was read. It cannot be recovered.
          </p>
        </div>
      </template>

      <!-- Protected State -->
      <template v-else>
        <div class="flex items-center gap-2">
          <svg
            class="size-5 text-gray-500"
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
          <p class="text-sm font-medium text-gray-600 dark:text-gray-400">
            This secret is encrypted and can only be viewed once by the recipient
          </p>
        </div>

        <div class="relative mt-3">
          <input
            class="w-full rounded-md border border-gray-200 bg-gray-50/50 px-3 py-2
                     font-mono text-gray-400 focus:outline-none focus:ring-2
                     focus:ring-brand-500 dark:border-gray-800 dark:bg-gray-800/50
                     dark:text-gray-500"
            value="•••••••••••••••••••"
            disabled
          />
          <div class="absolute right-2 top-1/2 -translate-y-1/2">
            <span class="text-xs font-medium text-gray-400 dark:text-gray-500">Encrypted</span>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
