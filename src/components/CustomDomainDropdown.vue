<script setup lang="ts">
import { ref } from 'vue';
import { Icon } from '@iconify/vue';


const props = defineProps({
  defaultDomain: {
    type: String,
    required: false,
    default: window.site_host,
  },
  availableDomains: {
    type: Array,
    required: false,
  },
});

const emit = defineEmits(['domainChange']);

const isOpen = ref(false);
const selectedDomain = ref(props.defaultDomain);

const toggleDropdown = () => {
  isOpen.value = !isOpen.value;
};

const selectDomain = (domain: string) => {
  selectedDomain.value = domain;
  emit('domainChange', domain);
  isOpen.value = false;
};
</script>

<template>
  <div class="relative inline-block text-left">
    <div>
      <button type="button"
              class="inline-flex justify-center w-full rounded-md border border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2 bg-white dark:bg-gray-800 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 dark:focus:ring-offset-gray-800"
              @click="toggleDropdown">
        <span class="text-sm text-brandcomp-600 dark:text-brandcomp-400 font-bold">{{ selectedDomain }}</span>
        <Icon icon="heroicons-solid:chevron-down"
              class="ml-2 -mr-1 h-5 w-5 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
      </button>
    </div>

    <div v-if="isOpen"
         class="origin-top-right absolute right-0 mt-2 w-56 rounded-md shadow-lg bg-white dark:bg-gray-800 ring-1 ring-black ring-opacity-5 dark:ring-gray-700 focus:outline-none">
      <div class="py-1"
           role="menu"
           aria-orientation="vertical"
           aria-labelledby="options-menu">
        <a v-for="domain in availableDomains"
           :key="domain"
           href="#"
           class="block px-4 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-white"
           role="menuitem"
           @click.prevent="selectDomain(domain)">
          {{ domain }}
        </a>
      </div>
    </div>
  </div>
</template>
