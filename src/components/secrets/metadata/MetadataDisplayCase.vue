<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models';

interface Props {
  metadata: Metadata;
  details: MetadataDetails;
}

defineProps<Props>()

</script>

<template>
  <div>
    <div
      v-if="details.show_secret"
      class="mb-4">
      <div v-if="details.can_decrypt">
        <p class="mb-2 italic text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.secret') }} ({{ metadata.secret_shortkey }}):
        </p>
        <textarea
          class="w-full resize-none rounded-md border border-gray-300 bg-gray-100 px-3 py-2 font-mono text-base leading-[1.2] tracking-wider focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          readonly
          :value="details.secret_value"
          :rows="details.display_lines"></textarea>
        <span class="text-sm text-gray-500 dark:text-gray-400">({{ $t('web.private.only_see_once') }})</span>
      </div>
      <div v-else>
        <input
          id="displayedsecret"
          class="w-full rounded-md border border-gray-300 bg-gray-100 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          :value="$t('web.private.this_msg_is_encrypted')"
          readonly
        />
      </div>
      <div v-if="details.is_truncated">
        <strong>{{ $t('web.COMMON.warning') }}</strong>
        {{ $t('web.COMMON.secret_was_truncated') }}
      </div>
    </div>

    <div
      v-if="!details.show_secret"
      class="mb-4">
      <p class="mb-2 text-gray-600 dark:text-gray-400">
        {{ $t('web.COMMON.secret') }} ({{ metadata.secret_shortkey }}):
      </p>
      <input
        class="w-full rounded-md border border-gray-300 bg-gray-100 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        value="*******************"
        disabled
      />
    </div>
  </div>
</template>
