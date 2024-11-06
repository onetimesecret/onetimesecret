<template>
  <section class="p-4 sm:p-6 lg:p-8 bg-white dark:bg-gray-900 rounded-lg shadow-sm"
           aria-labelledby="domains-heading">
    <div class="max-w-7xl mx-auto">
      <!-- Enhanced Header Section -->
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <div>
          <h1 id="domains-heading"
              class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
            Domains
          </h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Manage and configure your verified custom domains
          </p>
        </div>
        <router-link to="/account/domains/add"
                     class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium
                            rounded-lg bg-brand-600 text-white hover:bg-brand-700
                            focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
                            transition-colors duration-200 dark:hover:bg-brand-500
                            dark:focus:ring-offset-gray-900">
          <Icon icon="heroicons:plus-20-solid"
                class="w-4 h-4 mr-2"
                aria-hidden="true" />
          Add Domain
        </router-link>
      </div>

      <!-- Enhanced Table Section -->
      <div v-if="localDomains.length === 0" class="text-center py-8 text-gray-500">
        No domains found. Add a domain to get started.
      </div>

      <div v-else class="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-700">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Domain & Status
              </th>
              <th scope="col"
                  class="px-6 py-3 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                <div class="flex items-center justify-center">
                  Homepage Access
                  <div class="relative group ml-2">
                    <Icon icon="heroicons:question-mark-circle"
                          class="h-4 w-4 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300" />
                    <div class="invisible group-hover:visible absolute z-10 w-48 p-2 mt-2 -ml-24
                                bg-gray-900 dark:bg-gray-700 text-xs text-white rounded-md shadow-lg">
                      Control whether users can create secret links from your domain's homepage
                    </div>
                  </div>
                </div>
              </th>
              <th scope="col"
                  class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>

          <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
            <tr v-for="domain in localDomains"
                :key="domain.identifier"
                class="hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors duration-150">
              <td class="px-6 py-4">
                <div class="flex flex-col">
                  <router-link :to="{ name: 'AccountDomainBrand', params: { domain: domain.display_domain } }"
                               class="text-sm font-medium text-brandcomp-600 hover:text-brandcomp-700
                                    dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
                    {{ domain.display_domain }}
                  </router-link>
                  <div class="flex items-center mt-1 gap-2">
                    <DomainVerificationInfo mode="icon"
                                            :domain="domain" />
                    <span class="text-xs text-gray-500 dark:text-gray-400">
                      Added {{ formatDistanceToNow(new Date(Number(domain.created) * 1000), { addSuffix: true }) }}
                    </span>
                  </div>
                </div>
              </td>

              <td class="px-6 py-4">
                <div class="flex justify-center">
                  <button type="button"
                          :class="[
                            'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent',
                            'transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2',
                            {
                              'bg-brandcomp-600': getHomepageAccessStatus(domain),
                              'bg-gray-200 dark:bg-gray-700': !getHomepageAccessStatus(domain),
                              'opacity-50 cursor-not-allowed': isToggling(domain.identifier)
                            }
                          ]"
                          :disabled="isToggling(domain.identifier)"
                          role="switch"
                          :aria-checked="getHomepageAccessStatus(domain)"
                          @click.prevent="handleToggleHomepageCreation(domain)">
                    <span class="sr-only">
                      {{ getHomepageAccessStatus(domain) ? 'Disable' : 'Enable' }} homepage access
                    </span>
                    <span :class="[
                      'pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0',
                      'transition duration-200 ease-in-out',
                      getHomepageAccessStatus(domain) ? 'translate-x-5' : 'translate-x-0'
                    ]" />
                    <!-- Add loading spinner when toggling -->
                    <span v-if="isToggling(domain.identifier)"
                          class="absolute inset-0 flex items-center justify-center">
                      <svg class="animate-spin h-4 w-4 text-white"
                           xmlns="http://www.w3.org/2000/svg"
                           fill="none"
                           viewBox="0 0 24 24">
                        <circle class="opacity-25"
                                cx="12"
                                cy="12"
                                r="10"
                                stroke="currentColor"
                                stroke-width="4"></circle>
                        <path class="opacity-75"
                              fill="currentColor"
                              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z">
                        </path>
                      </svg>
                    </span>
                  </button>
                </div>
              </td>

              <td class="px-6 py-4 text-right text-sm">
                <MinimalDropdownMenu>
                  <template #menu-items>
                    <div class="py-1">
                      <MenuItem v-slot="{ active }">
                      <router-link :to="{ name: 'AccountDomainVerify', params: { domain: domain.display_domain } }"
                                   :class="[
                                    active ? 'bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-gray-100' : 'text-gray-700 dark:text-gray-300',
                                    'block px-4 py-2 text-sm'
                                  ]">
                        Verify Domain
                      </router-link>
                      </MenuItem>
                      <MenuItem v-slot="{ active }">
                      <router-link :to="{ name: 'AccountDomainBrand', params: { domain: domain.display_domain } }"
                                   :class="[
                                    active ? 'bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-gray-100' : 'text-gray-700 dark:text-gray-300',
                                    'block px-4 py-2 text-sm'
                                  ]">
                        Manage Brand
                      </router-link>
                      </MenuItem>
                      <MenuItem v-slot="{ active }">
                      <button @click="confirmDelete(domain)"
                              :class="[
                                active ? 'bg-gray-100 dark:bg-gray-700' : '',
                                'flex w-full items-center px-4 py-2 text-sm text-red-600 dark:text-red-400 hover:text-red-500'
                              ]"
                              :disabled="isSubmitting">
                        <Icon icon="heroicons:trash-20-solid"
                              class="mr-2 h-4 w-4"
                              aria-hidden="true" />
                        Remove
                      </button>
                      </MenuItem>
                    </div>
                  </template>
                </MinimalDropdownMenu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import { useDomainsTable } from '@/composables/useDomainsTable';
import type { CustomDomain } from '@/types/onetime';
import { MenuItem } from '@headlessui/vue';
import { Icon } from '@iconify/vue';
import { formatDistanceToNow } from 'date-fns';
import { ref, watch, onMounted } from 'vue';
import { useDomainsStore } from '@/stores/domainsStore';
import DomainVerificationInfo from './DomainVerificationInfo.vue';
import MinimalDropdownMenu from './MinimalDropdownMenu.vue';

const props = defineProps<{
  domains: CustomDomain[];
}>();

const domainsStore = useDomainsStore();
const localDomains = ref<CustomDomain[]>(props.domains);
const debugError = ref<string | null>(null);

// Reactive watch for store domains changes
watch(() => domainsStore.domains, (newDomains) => {
  console.log('[DomainsTable] Store domains changed:', newDomains);
  localDomains.value = newDomains;
}, { deep: true, immediate: true });

// Fetch domains on component mount if not provided
onMounted(async () => {
  console.log('[DomainsTable] Mounted. Initial props:', props.domains);
  try {
    if (localDomains.value.length === 0) {
      console.log('[DomainsTable] No domains in props, fetching from store');
      await domainsStore.refreshDomains();
      localDomains.value = domainsStore.domains;
      console.log('[DomainsTable] Domains after refresh:', localDomains.value);
    }
  } catch (error) {
    console.error('[DomainsTable] Failed to fetch domains:', error);
    debugError.value = error instanceof Error
      ? `Failed to fetch domains: ${error.message}`
      : 'An unknown error occurred while fetching domains';
  }
});

const {
  isToggling,
  isSubmitting,
  toggleHomepageCreation,
  confirmDelete
} = useDomainsTable(localDomains.value);

// Helper method to safely get homepage access status
const getHomepageAccessStatus = (domain: CustomDomain): boolean => {
  return domain?.brand?.allow_public_homepage ?? false;
};

const handleToggleHomepageCreation = async (domain: CustomDomain) => {
  try {
    // Optimistically update the local state before API call
    const currentDomain = localDomains.value.find(d => d.identifier === domain.identifier);
    if (currentDomain && currentDomain.brand) {
      currentDomain.brand.allow_public_homepage = !getHomepageAccessStatus(domain);
    }

    await toggleHomepageCreation(domain);

    // Refresh domains to ensure final state
    await domainsStore.refreshDomains();
  } catch (error) {
    console.error('Failed to toggle homepage creation:', error);
    // Revert the optimistic update if the API call fails
    const currentDomain = localDomains.value.find(d => d.identifier === domain.identifier);
    if (currentDomain && currentDomain.brand) {
      currentDomain.brand.allow_public_homepage = getHomepageAccessStatus(domain);
    }
  }
};
</script>
