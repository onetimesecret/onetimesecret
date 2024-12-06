
<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { ref } from 'vue';

interface DomainProps {
  defaultDomain: string;
  availableDomains: string[];
}

const props = withDefaults(defineProps<DomainProps>(), {
  defaultDomain: window.site_host as string,
  availableDomains: () => [],
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
      <button
        type="button"
        class="inline-flex w-full justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 dark:focus:ring-offset-gray-800"
        @click="toggleDropdown">
        <span class="text-sm font-bold text-brandcomp-600 dark:text-brandcomp-400">{{ selectedDomain }}</span>
        <Icon
          icon="heroicons-solid:chevron-down"
          class="-mr-1 ml-2 size-5 text-gray-400 dark:text-gray-500"
          aria-hidden="true"
        />
      </button>
    </div>

    <div
      v-if="isOpen"
      class="absolute right-0 mt-2 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700">
      <div
        class="py-1"
        role="menu"
        aria-orientation="vertical"
        aria-labelledby="options-menu">
        <a
          v-for="domain in availableDomains"
          :key="domain"
          href="#"
          class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white"
          role="menuitem"
          @click.prevent="selectDomain(domain)">
          {{ domain }}
        </a>
      </div>
    </div>
  </div>
</template>
