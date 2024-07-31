<script setup lang="ts">
import { ref } from 'vue';
import { Icon } from '@iconify/vue';

const isExpanded = ref(false);
const toggleExpand = () => {
  isExpanded.value = !isExpanded.value;
};

interface Props {
  displayDomain: string | null;
  clusterIpAddress: string | null;
  clusterName: string | null;
}

const props = withDefaults(defineProps<Props>(), {
  displayDomain: 'LINKS.EXAMPLE.COM',
  clusterIpAddress: '1.2.3.4',
  clusterName: 'CLUSTERNAME',
});
</script>

<template>
  <div class="mb-4 bg-white dark:bg-gray-800 shadow sm:rounded-lg relative">
    <div class="px-4 py-5 sm:p-4">
      <button @click="toggleExpand"
              class="flex items-center text-lg font-medium text-gray-900 dark:text-gray-100 hover:text-brandcomp-600 dark:hover:text-brandcomp-400 focus:outline-none">
        <Icon :icon="isExpanded ? 'heroicons:chevron-down' : 'heroicons:chevron-right'"
              class="h-5 w-5 mr-2" />
        {{ isExpanded ? 'Hide details' : 'Expand for more info' }}
      </button>

      <div v-show="isExpanded"
           class="absolute left-4 right-4 mt-2 bg-gray-50 dark:bg-gray-700 shadow-lg rounded-lg overflow-hidden transition-all duration-300 ease-in-out z-10 border border-gray-200 dark:border-gray-600"
           :class="{ 'max-h-0': !isExpanded, 'max-h-[500px]': isExpanded }">
        <div class="px-6 py-6">
          <div class="max-w-xl text-base text-gray-600 dark:text-gray-300">
            <p>
              In order to connect your domain, you'll need to have a DNS A record that points
              <span class="font-bold bg-white dark:bg-gray-800 px-2 text-brand-600 dark:text-brand-400">{{ props.displayDomain }}</span> at <span
                    :title="props.clusterName" class="bg-white dark:bg-gray-800 px-2">{{ props.clusterIpAddress }}</span>. If you already have an A record for
              that
              address, please change it to point at <span :title="props.clusterName" class="bg-white dark:bg-gray-800 px-2">{{ props.clusterIpAddress }}</span>
              and remove any other A, AAAA,
              or CNAME records for that exact address.
            </p>
          </div>
          <div class="mt-4 text-sm">
            <a href="#"
               class="font-medium text-brandcomp-600 hover:text-brandcomp-500 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
              Learn more about DNS configuration <span aria-hidden="true">&rarr;</span>
            </a>
          </div>
          <div class="mt-5 flex items-start bg-white dark:bg-gray-800 p-4 rounded-md">
            <Icon icon="mdi:information-outline"
                  class="h-5 w-5 text-brand-400 mr-2 mt-0.5 flex-shrink-0"
                  aria-hidden="true" />
            <p class="text-sm text-gray-500 dark:text-gray-400">
              It may take a few minutes for your SSL certificate to take effect once you've pointed your DNS A record.
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
