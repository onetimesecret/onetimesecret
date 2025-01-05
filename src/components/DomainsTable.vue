<script setup lang="ts">
import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';
import MinimalDropdownMenu from '@/components/MinimalDropdownMenu.vue';
import { WindowService } from '@/services/window.service'
import type { CustomDomain } from '@/schemas/models/domain';
import { MenuItem } from '@headlessui/vue';
import { Icon } from '@iconify/vue';
import { formatDistanceToNow } from 'date-fns';

const cust = WindowService.get('cust'); // Used for feature flags

defineProps<{
  domains: CustomDomain[];
  isLoading: boolean;
}>();

const emit = defineEmits<{
  (e: 'confirm-delete', domainId: string): void;
  (e: 'toggle-homepage', domain: CustomDomain): void;
}>();

const handleDelete = (domainId: string) => {
  emit('confirm-delete', domainId);
};
</script>

<template>
  <section
    class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-900 sm:p-6 lg:p-8"
    aria-labelledby="domains-heading">
    <!-- Header Section -->
    <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1
          id="domains-heading"
          class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
          Domains
        </h1>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          Manage and configure your verified custom domains
        </p>
      </div>
      <router-link
        to="/domains/add"
        class="inline-flex items-center justify-center rounded-lg bg-brand-600 px-4 py-2 font-brand
                            text-base font-medium text-white transition-colors
                            duration-200 hover:bg-brand-700 focus:outline-none focus:ring-2
                            focus:ring-brand-500 focus:ring-offset-2 dark:hover:bg-brand-500
                            dark:focus:ring-offset-gray-900">
        <Icon
          icon="heroicons:plus-20-solid"
          class="mr-2 size-4"
          aria-hidden="true"
        />
        Add Domain
      </router-link>
    </div>

    <!-- When no domains, use the Add a Domain button -->
    <div
      v-if="domains.length === 0"
      class="py-8 text-center text-gray-500">
      No domains found. Add a domain to get started.
    </div>

    <!-- List domains -->
    <div
      v-else
      class="relative rounded-lg border border-gray-200 dark:border-gray-700">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="bg-gray-50 font-brand dark:bg-gray-800">
          <tr>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium tracking-wider
                  text-gray-500 dark:text-gray-400">
              <span class="uppercase">Domain & Status</span>
            </th>

            <th
              scope="col"
              class="px-6 py-3 text-center text-xs font-medium tracking-wider text-gray-500
                  dark:text-gray-400">
              <div
                v-if="cust?.feature_flags?.homepage_toggle"
                class="flex items-center justify-center">
                <span class="uppercase">Homepage Access</span>
                <div class="group relative ml-2">
                  <Icon
                    icon="heroicons:question-mark-circle"
                    class="size-4 text-gray-400  transition-colors duration-200 hover:text-gray-500
                        dark:text-gray-400 dark:hover:text-gray-300"
                  />
                  <div
                    class="invisible absolute z-10 -ml-24 mt-2 w-48 rounded-md bg-white
                                    p-2 text-xs text-gray-900 shadow-lg ring-1 ring-black/5
                                    transition-opacity duration-200 group-hover:visible dark:bg-gray-800 dark:text-gray-100
                                    dark:shadow-gray-900/50 dark:ring-white/10">
                    Control whether users can create secret links from your domain's homepage
                  </div>
                </div>
              </div>
            </th>

            <th
              scope="col"
              class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider
                  text-gray-500 dark:text-gray-400">
              Actions
            </th>
          </tr>
        </thead>

        <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
          <tr
            v-for="domain in domains"
            :key="domain.identifier"
            class="transition-colors duration-150 hover:bg-gray-50 dark:hover:bg-gray-800">
            <!-- Domain & Status -->
            <td class="px-6 py-4">
              <div class="flex flex-col">
                <router-link
                  :to="{ name: 'DomainBrand', params: { domain: domain.display_domain } }"
                  class="font-brand text-lg text-brandcomp-600 hover:text-brandcomp-700
                                        dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
                  {{ domain.display_domain }}
                </router-link>
                <div class="mt-1 flex items-center gap-2">
                  <DomainVerificationInfo
                    mode="icon"
                    :domain="domain"
                  />
                  <span class="text-xs text-gray-500 dark:text-gray-400">
                    Added {{ formatDistanceToNow(domain.created, { addSuffix: true }) }}
                  </span>
                </div>
              </div>
            </td>

            <!-- Homepage Access -->
            <td class="px-6 py-4 text-center">
              <div v-if="cust?.feature_flags?.homepage_toggle">
                <!-- Add your homepage access toggle/content here -->
              </div>
            </td>

            <!-- Actions -->
            <td class="px-6 py-4 text-right">
              <MinimalDropdownMenu>
                <template #menu-items>
                  <div class="py-1">
                    <MenuItem v-slot="{ active }">
                      <router-link
                        :to="{ name: 'DomainVerify', params: { domain: domain.display_domain } }"
                        :class="[
                          active ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white' : 'text-gray-700 dark:text-gray-200',
                          'block px-4 py-2 text-sm transition-colors duration-200'
                        ]">
                        Verify Domain
                      </router-link>
                    </MenuItem>
                    <MenuItem v-slot="{ active }">
                      <router-link
                        :to="{ name: 'DomainBrand', params: { domain: domain.display_domain } }"
                        :class="[
                          active ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white' : 'text-gray-700 dark:text-gray-200',
                          'block px-4 py-2 text-sm transition-colors duration-200'
                        ]">
                        Manage Brand
                      </router-link>
                    </MenuItem>
                    <MenuItem v-slot="{ active }">
                      <button
                        @click="handleDelete(domain.display_domain)"
                        :class="[
                          active ? 'bg-gray-100 dark:bg-gray-800' : '',
                          'flex w-full items-center px-4 py-2 text-sm text-red-600 transition-colors duration-200 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300'
                        ]"
                        :disabled="isLoading">
                        <Icon
                          icon="heroicons:trash-20-solid"
                          class="mr-2 size-4"
                          aria-hidden="true"
                        />
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
  </section>
</template>
