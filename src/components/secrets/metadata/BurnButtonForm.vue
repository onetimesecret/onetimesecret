
<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models';

interface Props {
  metadata: Metadata;
  details: MetadataDetails;
}

defineProps<Props>()

</script>

<template>
  <div v-if="!details.is_destroyed">
    <router-link
      :to="{ name: 'Burn secret', params: { metadataKey: metadata.key } }"
      class="mb-4 block w-full rounded-md bg-yellow-400 px-4 py-2
      text-center text-base text-gray-800
      hover:bg-yellow-300 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800">
      <svg
        class="mr-2 inline-block size-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg"
        width="20"
        height="20">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"
        />
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9.879 16.121A3 3 0 1012.015 11L11 14H9c0 .768.293 1.536.879 2.121z"
        />
      </svg>
      {{ $t('web.COMMON.burn_this_secret') }}
    </router-link>

    <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
      * {{ $t('web.COMMON.burn_this_secret_hint') }}.
    </p>

  </div>
</template>
