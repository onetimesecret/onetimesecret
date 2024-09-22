<script setup lang="ts">
import { useWindowProps } from '@/composables/useWindowProps';


const { metadata_record_count, domains_enabled, plan, custom_domains_record_count } = useWindowProps(['shrimp', 'metadata_record_count', 'domains_enabled', 'plan', 'custom_domains_record_count']);

</script>

<template>

  <nav class="mb-6">
    <ul class="text-xl font-brand flex space-x-4">
      <li>
        <router-link to="/"
                     class="text-gray-700 font-bold underline dark:text-gray-300 hover:underline dark:hover:text-grey-500 transition-colors">
          {{ $t('web.COMMON.title_home') }}
        </router-link>
      </li>
      <li>
        <router-link to="/recent"
                     class="text-gray-700 dark:text-gray-300 hover:underline hover:text-grey-500 dark:hover:text-grey-500 transition-colors flex items-center">
          <span class="block sm:hidden">{{ $t('web.COMMON.secret') }}</span>
          <span class="hidden sm:block">{{ $t('web.COMMON.title_recent_secrets') }}</span>
          <span
                class="ml-2 bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-full px-2 py-0.5 text-xs font-medium">{{ metadata_record_count }}</span>
        </router-link>
      </li>

      <li v-if="domains_enabled && plan.paid">
        <router-link to="/account/domains"
                     class="text-gray-700 dark:text-gray-300 hover:underline hover:text-grey-500 dark:hover:text-grey-500 transition-colors flex items-center">
          <span class="block sm:hidden">Domains</span>
          <span class="hidden sm:block">Custom Domains</span>
          <span
                class="ml-2 bg-gray-200 font-medium dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-full px-2 py-0.5 text-xs">{{ custom_domains_record_count }}</span>
        </router-link>
      </li>
    </ul>
  </nav>

</template>
