<template>
  <div ref="dropdownRef"
       class="relative inline-flex items-center space-x-2 px-3 py-1 rounded-full
           bg-gray-100 text-base font-medium shadow-sm
           text-gray-500 dark:text-gray-400
           dark:bg-gray-800
           transition-all duration-100 ease-in-out hover:shadow-md">
    <span class="sr-only">Current jurisdiction:</span>
    <button @click="toggleDropdown"
            class="flex items-center space-x-2
             focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
             dark:focus:ring-brand-400"
            :aria-expanded="isOpen"
            aria-haspopup="listbox">
      <Icon :icon="currentJurisdiction.icon"
            class="h-5 w-5"
            aria-hidden="true" />

      <!-- Current Jurisdiction -->
      <span>{{ currentJurisdiction.display_name }}</span>

      <svg xmlns="http://www.w3.org/2000/svg"
           class="h-4 w-4 transform -rotate-90"
           viewBox="0 0 20 20"
           fill="currentColor"
           aria-hidden="true">
        <path fill-rule="evenodd"
              d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
              clip-rule="evenodd" />
      </svg>

    </button>
    <transition enter-active-class="transition ease-out duration-100"
                enter-from-class="transform opacity-0 scale-95"
                enter-to-class="transform opacity-100 scale-100"
                leave-active-class="transition ease-in duration-75"
                leave-from-class="transform opacity-100 scale-100"
                leave-to-class="transform opacity-0 scale-95">
      <ul v-if="isOpen"
          class="absolute z-10 bottom-full left-0 w-full mb-1 py-1 max-h-60 overflow-auto
               bg-white rounded-md shadow-lg text-base ring-1 ring-black ring-opacity-5
               dark:bg-gray-700 focus:outline-none sm:text-sm"
          tabindex="-1"
          role="listbox"
          aria-labelledby="listbox-label"
          aria-activedescendant="listbox-option-0">

        <!-- List Title -->
        <li
            class="px-3 py-2 text-xs font-semibold font-brand text-gray-700 dark:text-gray-100 uppercase tracking-wider">
          Regions
        </li>

        <!-- List Options -->
        <li v-for="jurisdiction in jurisdictions"
            :key="jurisdiction.identifier"
            class="relative py-2 pl-3 pr-9 cursor-default select-none font-brand text-base
                  text-gray-700 dark:text-gray-50
                 hover:bg-brand-100 dark:hover:bg-brandcompdim-800 transition-colors duration-200"
            :class="{ 'bg-brand-50 dark:bg-brandcompdim-900': currentJurisdiction.identifier === jurisdiction.identifier }"
            role="option"
            :aria-selected="currentJurisdiction.identifier === jurisdiction.identifier">
          <a :href="`https://${jurisdiction.domain}/signup`"
             :title="`Continue to ${jurisdiction.domain}`">
            <span class="flex items-center">

              <Icon :icon="jurisdiction.icon"
                    class="mr-2 h-5 w-5"
                    aria-hidden="true" />

              <!-- Jurisdiction Name -->
              <span class="block truncate"
                    :class="{ 'font-semibold': currentJurisdiction.identifier === jurisdiction.identifier }">
                {{ jurisdiction.display_name }}
              </span>
            </span>
            <span v-if="currentJurisdiction.identifier === jurisdiction.identifier"
                  class="absolute inset-y-0 right-0 flex items-center pr-4 text-brand-600
                   dark:text-brand-400">
              <svg class="h-5 w-5"
                   xmlns="http://www.w3.org/2000/svg"
                   viewBox="0 0 20 20"
                   fill="currentColor"
                   aria-hidden="true">
                <path fill-rule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clip-rule="evenodd" />
              </svg>
            </span>
          </a>
        </li>
      </ul>
    </transition>
  </div>
</template>

<script setup lang="ts">
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { Icon } from '@iconify/vue';
import { useClickOutside } from '@/composables/useClickOutside';
import { computed, ref } from 'vue';

const jurisdictionStore = useJurisdictionStore();

const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const isOpen = ref(false);
const dropdownRef = ref<HTMLElement | null>(null);

const toggleDropdown = () => {
  isOpen.value = !isOpen.value;
};

const closeDropdown = () => {
  isOpen.value = false;
};

useClickOutside(dropdownRef, closeDropdown);
</script>
