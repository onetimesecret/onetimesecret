
<template>

  <div v-if="!details.is_destroyed">

    <router-link
      :to="{ name: 'Burn secret', params: { metadataKey: metadata.key } }"
      class="block w-full px-4 py-2 mb-4 text-center text-base
      bg-yellow-400 rounded-md text-gray-800
      hover:bg-yellow-300 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800">
      <svg
        class="inline-block w-5 h-5 mr-2"
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
          d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"></path>
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9.879 16.121A3 3 0 1012.015 11L11 14H9c0 .768.293 1.536.879 2.121z"></path>
      </svg>
      {{$t('web.COMMON.burn_this_secret')}}
    </router-link>

    <p class="text-sm text-gray-500 dark:text-gray-400 mb-4">
      * {{$t('web.COMMON.burn_this_secret_hint')}}.
    </p>

    <hr class="w-1/4 my-4 mx-auto border-gray-200 dark:border-gray-600" />
  </div>
</template>

<script setup lang="ts">
import type { MetadataData, MetadataDetails } from '@/types'

interface Props {
  metadata: MetadataData;
  details: MetadataDetails;
}

defineProps<Props>()

</script>
