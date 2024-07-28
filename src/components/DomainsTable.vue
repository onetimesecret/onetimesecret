<template>
  <div class="px-4 sm:px-6 lg:px-8 dark:bg-gray-900">
    <div class="sm:flex sm:items-center">
      <div class="sm:flex-auto">
        <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-gray-100">Domains</h1>
        <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">These are your verified custom domains.</p>
      </div>
      <div class="mt-4 sm:ml-16 sm:mt-0 sm:flex-none">
        <a href="/account/domains/add"
                class="block rounded-md bg-brandcomp-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-sm hover:bg-brandcomp-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brandcomp-600 dark:bg-brandcomp-500 dark:hover:bg-brandcomp-400">
                Add domain
      </a>
      </div>
    </div>
    <div class="-mx-4 mt-10 ring-1 ring-gray-300 sm:mx-0 sm:rounded-lg dark:ring-gray-700">
      <table class="min-w-full divide-y divide-gray-300 dark:divide-gray-700">
        <thead>
          <tr>
            <th scope="col"
                class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6 dark:text-gray-100">Domain</th>
            <th scope="col"
                class="hidden px-3 py-3.5 text-left text-sm font-semibold text-gray-900 lg:table-cell dark:text-gray-100">Status</th>
            <th scope="col"
                class="hidden px-3 py-3.5 text-left text-sm font-semibold text-gray-900 lg:table-cell dark:text-gray-100">Added</th>
            <th scope="col"
                class="relative py-3.5 pl-3 pr-4 sm:pr-6">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
          <tr v-for="(domain, domainIdx) in domains" :key="domain.identifier" :tabindex="domainIdx">
            <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-6 dark:text-gray-100">
              {{ domain.display_domain }}
            </td>
            <td class="hidden whitespace-nowrap px-3 py-4 text-sm text-gray-500 lg:table-cell dark:text-gray-300">
              {{ domain.verified || 'pending' }}
            </td>
            <td class="hidden whitespace-nowrap px-3 py-4 text-sm text-gray-500 lg:table-cell dark:text-gray-300">
              {{ formatRelativeTime(domain.created) }}
            </td>
            <td class="whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6">
              <a href="#" class="text-brandcomp-600 hover:text-brandcomp-900 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">Edit<span class="sr-only">, {{ domain.name }}</span></a>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { CustomDomain } from '@/types/onetime'

defineProps({
  domains: Array<CustomDomain>,
})


const formatRelativeTime = (epochSeconds: number): string => {
  const date = new Date(epochSeconds * 1000); // Convert seconds to milliseconds
  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

  if (diffInSeconds < 60) {
    return rtf.format(-diffInSeconds, 'second');
  } else if (diffInSeconds < 3600) {
    return rtf.format(-Math.floor(diffInSeconds / 60), 'minute');
  } else if (diffInSeconds < 86400) {
    return rtf.format(-Math.floor(diffInSeconds / 3600), 'hour');
  } else {
    return rtf.format(-Math.floor(diffInSeconds / 86400), 'day');
  }
}

</script>
