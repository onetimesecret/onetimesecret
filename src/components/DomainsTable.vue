<template>
  <section class="p-4 sm:p-6 lg:p-8 bg-white dark:bg-gray-900 rounded-lg"
           aria-labelledby="domains-heading">
    <div class="max-w-7xl mx-auto">
      <!-- Header Section -->
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 id="domains-heading"
              class="text-2xl font-bold text-gray-900 dark:text-white">
            Domains
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            These are your verified custom domains
          </p>
        </div>
        <router-link to="/account/domains/add"
                     class="inline-flex items-center justify-center px-4 py-2 text-sm font-semibold rounded-lg
                 bg-brand-500 text-white hover:bg-brand-600 focus:outline-none focus:ring-2
                 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-200
                 dark:hover:bg-brand-400 dark:focus:ring-offset-gray-900">
          <Icon icon="heroicons:plus-20-solid"
                class="w-5 h-5 mr-2"
                aria-hidden="true" />
          <span>Add Domain</span>
        </router-link>
      </div>

      <!-- Table Section -->
      <div class="mt-8 overflow-hidden rounded-lg border border-gray-200 dark:border-gray-700 shadow-sm">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
            <thead class="bg-gray-50 dark:bg-gray-800">
              <tr>
                <th scope="col"
                    class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-gray-200 min-w-[200px]">
                  Domain
                </th>
                <th scope="col"
                    class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-gray-200 w-32">
                  Status
                </th>
                <th scope="col"
                    class="hidden sm:table-cell px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-gray-200 w-40">
                  Added
                </th>
                <th scope="col"
                    class="px-6 py-3 text-right text-sm font-semibold text-gray-900 dark:text-gray-200 w-20">
                  <span class="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
              <tr v-for="domain in domains"
                  :key="domain.identifier"
                  class="group hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors duration-150">
                <td class="px-6 py-4 whitespace-nowrap">
                  <router-link :to="{ name: 'AccountDomainBrand', params: { domain: domain.display_domain } }"
                               class="text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300
                           font-medium transition-colors duration-150">
                    {{ domain.display_domain }}
                  </router-link>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <DomainVerificationInfo mode="icon"
                                          :domain="domain" />
                </td>
                <td class="hidden sm:table-cell px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                  {{ formatRelativeTime(Number(domain.created)) }}
                </td>
                <td
                    class="px-6 py-4 whitespace-nowrap text-right sticky right-0 bg-white dark:bg-gray-900 group-hover:bg-gray-50 dark:group-hover:bg-gray-800">
                  <MinimalDropdownMenu>
                    <template #menu-items>
                      <MenuItem v-slot="{ active }">
                      <router-link :to="{ name: 'AccountDomainVerify', params: { domain: domain.display_domain }}"
                                   :class="[
                                    active ? 'bg-gray-100 dark:bg-gray-700' : '',
                            'block px-4 py-2 text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-700'
                          ]">
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
  </section>
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
