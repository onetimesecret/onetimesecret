<template>
  <nav class="mb-6">
    <ul v-if="authenticated"
        class="text-xl font-brand flex space-x-4">
      <li>
        <router-link to="/dashboard"
                     :class="[
                      'transition-colors',
                      isActiveRoute('/dashboard')
                        ? 'font-bold underline'
                        : 'hover:underline hover:text-grey-500 dark:hover:text-grey-500'
                    ]">
          {{ $t('web.COMMON.title_home') }}
        </router-link>
      </li>
      <li>
        <router-link to="/recent"
                     :class="[
                      'flex items-center transition-colors',
                      isActiveRoute('/recent')
                        ? 'font-bold underline'
                        : 'hover:underline hover:text-grey-500 dark:hover:text-grey-500'
                    ]">
          <span class="block sm:hidden">{{ $t('web.COMMON.secret') }}</span>
          <span class="hidden sm:block">{{ $t('web.COMMON.title_recent_secrets') }}</span>
          <span
                class="ml-2 bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-full px-2 py-0.5 text-xs font-medium">{{ metadata_record_count }}</span>
        </router-link>
      </li>
      <li v-if="domains_enabled && planAllowsCustomDomains">
        <router-link to="/account/domains"
                     :class="[
                      'flex items-center transition-colors',
                      isActiveRoute('/account/domains')
                        ? 'font-bold underline'
                        : 'hover:underline hover:text-grey-500 dark:hover:text-grey-500'
                    ]">
          <span class="block sm:hidden">Domains</span>
          <span class="hidden sm:block">Custom Domains</span>
          <span
                class="ml-2 bg-gray-200 font-medium dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-full px-2 py-0.5 text-xs">{{ custom_domains_record_count }}</span>
        </router-link>
      </li>
    </ul>
  </nav>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useWindowProps } from '@/composables/useWindowProps';

const { authenticated, metadata_record_count, domains_enabled, plan, custom_domains_record_count } = useWindowProps(['authenticated', 'metadata_record_count', 'domains_enabled', 'plan', 'custom_domains_record_count']);

const planAllowsCustomDomains = computed(() => plan.value.options?.custom_domains === true);

const route = useRoute()

const isActiveRoute = (path: string) => route.path === path

console.debug('plop', isActiveRoute('/account/domains'))
</script>
