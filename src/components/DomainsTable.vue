<template>
  <div class="bg-white px-4 py-8 sm:px-6 lg:px-8 dark:bg-gray-900">
    <div class="sm:flex sm:items-center sm:justify-between">
      <div class="sm:flex-auto">
        <h1 class="text-2xl font-bold leading-7 text-gray-900 dark:text-white">Domains</h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">These are your verified custom domains.</p>
      </div>
      <div class="mt-4 sm:mt-0">
        <router-link to="/account/domains/add"
          class="inline-flex items-center rounded-md px-3 py-2 text-sm font-semibold text-white
          shadow-sm bg-brand-600 hover:bg-brand-500 focus-visible:outline focus-visible:outline-2
          focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500
          dark:hover:bg-brand-400 transition-colors duration-200">
          <span class="mr-2">Add Domain</span>
          <span class="sr-only">Add a new domain</span>
          <Icon icon="heroicons:plus-20-solid"
                class="h-5 w-5"
                aria-hidden="true" />
        </router-link>
      </div>
    </div>
    <div class="mt-8 flow-root min-h-72">
      <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
        <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
          <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 sm:rounded-lg">
            <table class="min-w-full divide-y divide-gray-300 dark:divide-gray-700">
              <thead class="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th scope="col"
                    class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900
                    dark:text-gray-200 sm:pl-6">
                    Domain</th>
                  <th scope="col"
                    class="hidden px-3 py-3.5 text-left text-sm font-semibold text-gray-900
                    dark:text-gray-200 lg:table-cell">
                    Status</th>
                  <th scope="col"
                    class="hidden px-3 py-3.5 text-left text-sm font-semibold text-gray-900
                    dark:text-gray-200 lg:table-cell">
                    Added</th>
                  <th scope="col"
                    class="relative py-3.5 pl-3 pr-4 sm:pr-6">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
                <tr v-for="(domain, domainIdx) in domains"
                    :key="domain.identifier"
                    :class="domainIdx % 2 === 0 ? 'bg-white dark:bg-gray-900' : 'bg-gray-50 dark:bg-gray-800'"
                    tabindex="0">
                  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-extrabold sm:pl-6">
                    <router-link :to="{ name: 'AccountDomainBrand', params: { domain: domain.display_domain } }"
                      class="text-brandcomp-600 hover:text-brandcomp-500 dark:text-brandcomp-400
                      dark:hover:text-brandcomp-300 transition-colors duration-200">
                      {{ domain.display_domain }}
                    </router-link>
                  </td>

                  <td class="hidden whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400 lg:table-cell">
                    <DomainVerificationInfo mode="icon"
                                            :domain="domain" />
                  </td>
                  <td class="hidden whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400 lg:table-cell">
                    {{ formatRelativeTime(Number(domain.created)) }}
                  </td>
                  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6">
                    <MinimalDropdownMenu>
                      <template #menu-items>
                        <MenuItem v-slot="{ active }">
                        <router-link :to="{ name: 'AccountDomainVerify', params: { domain: domain.display_domain } }"
                                     :class="[active ? 'bg-gray-100 text-gray-900' : 'text-gray-700', 'block px-4 py-2 text-sm']">
                          Review verification steps
                        </router-link>
                        </MenuItem>
                        <MenuItem v-slot="{ active }">
                        <router-link :to="{ name: 'AccountDomainBrand', params: { domain: domain.display_domain } }"
                                     :class="[active ? 'bg-gray-100 text-gray-900' : 'text-gray-700', 'block px-4 py-2 text-sm']">
                          Manage Brand
                        </router-link>
                        </MenuItem>
                        <form @submit.prevent="(event) => submitForm(event)"
                              :action="`/api/v2/account/domains/${domain.display_domain}/remove`">
                          <input type="hidden"
                                 name="shrimp"
                                 :value="csrfStore.shrimp" />
                          <MenuItem v-slot="{ active }">
                          <button type="submit"
                                  :class="[
                                    active ? 'bg-gray-100 text-gray-900' : 'text-gray-700',
                                    'flex w-full items-center px-4 py-2 text-left text-sm text-red-600 hover:text-red-500'
                                  ]"
                                  :disabled="isSubmitting">
                            <Icon icon="heroicons:trash-20-solid"
                                  class="mr-2 h-5 w-5 text-red-500"
                                  aria-hidden="true" />
                            <span>Remove</span>
                          </button>
                          </MenuItem>
                        </form>
                      </template>
                    </MinimalDropdownMenu>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>


<script setup lang="ts">
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import type { CustomDomain } from '@/types/onetime';
import { MenuItem } from '@headlessui/vue';
import { Icon } from '@iconify/vue';
import { useRouter } from 'vue-router';
import DomainVerificationInfo from './DomainVerificationInfo.vue';
import MinimalDropdownMenu from './MinimalDropdownMenu.vue';

const csrfStore = useCsrfStore();

const router = useRouter();

defineProps<{
  domains: CustomDomain[];
}>();


const { isSubmitting, submitForm } = useFormSubmission({
  successMessage: 'Domain removed successfully',
  onSuccess: () => {
    // Refresh the current route
    router.go(0);
  },
});

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
