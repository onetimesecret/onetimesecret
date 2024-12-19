<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata'

// Extend MetadataDetails to include truncation property
interface ExtendedMetadataDetails extends MetadataDetails {
  is_truncated?: boolean;
}

interface Props {
  metadata: Metadata;
  details: ExtendedMetadataDetails;
}

defineProps<Props>();
</script>

<template>
  <div>
    <div
      v-if="details.show_secret"
      class="mb-4">
      <div v-if="details.can_decrypt" class="relative">
        <p class="mb-2 italic text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.secret') }} ({{ metadata.secret_shortkey }}):
        </p>
        <div class="relative">
          <textarea
            class="w-full resize-none rounded-md border-2 border-emerald-300 bg-emerald-50/50 px-3 py-2 font-mono text-base leading-[1.2] tracking-wider shadow-sm focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-emerald-800 dark:bg-emerald-950/30 dark:text-white"
            readonly
            :value="details.secret_value"
            :rows="details.display_lines || 3"></textarea>
          <div class="absolute right-2 top-2">
            <div class="h-2 w-2 rounded-full bg-emerald-400 dark:bg-emerald-500"></div>
          </div>
        </div>
        <span class="mt-1 block text-sm font-medium text-emerald-600 dark:text-emerald-400">({{ $t('web.private.only_see_once') }})</span>
      </div>
      <div v-else-if="details.is_burned" class="relative">
        <input
          id="displayedsecret"
          class="w-full rounded-md border-2 border-red-300 bg-red-50/50 px-3 py-2 text-red-700 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-red-900 dark:bg-red-950/30 dark:text-red-400"
          :value="$t('web.private.this_msg_is_encrypted')"
          readonly
        />
        <div class="absolute right-2 top-1/2 -translate-y-1/2">
          <div class="h-2 w-2 rounded-full bg-red-500 dark:bg-red-600"></div>
        </div>
        <span class="mt-1 block text-sm font-medium text-red-600 dark:text-red-400">{{ $t('web.COMMON.burned') }}</span>
      </div>
    </div>

    <div
      v-if="!details.show_secret"
      class="mb-4">
      <p class="mb-2 text-gray-600 dark:text-gray-400">
        {{ $t('web.COMMON.secret') }} ({{ metadata.secret_shortkey }}):
      </p>
      <div class="relative">
        <input
          class="w-full rounded-md border-2 border-gray-200 bg-gray-50 px-3 py-2 text-gray-400 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-700 dark:bg-gray-800/50 dark:text-gray-500"
          value="*******************"
          disabled
        />
        <div class="absolute right-2 top-1/2 -translate-y-1/2">
          <div class="h-2 w-2 rounded-full bg-gray-300 dark:bg-gray-600"></div>
        </div>
      </div>
    </div>
  </div>
</template>
