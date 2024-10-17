<template>
  <div class="relative inline-flex items-center space-x-2 px-3 py-1 rounded-full
           bg-gray-100 text-base font-medium text-gray-700 shadow-sm
           dark:bg-gray-800 dark:text-gray-300
           transition-all duration-100 ease-in-out hover:shadow-md">
    <span class="sr-only">Current jurisdiction:</span>
    <button @click="toggleDropdown"
            class="flex items-center space-x-2
             focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
             dark:focus:ring-brand-400"
            :aria-expanded="isOpen"
            aria-haspopup="listbox">
      <span>{{ selectedJurisdiction }}</span>
      <svg xmlns="http://www.w3.org/2000/svg"
           class="h-4 w-4 transform -rotate-90"
           viewBox="0 0 20 20"
           fill="currentColor"
           aria-hidden="true">
        <path fill-rule="evenodd"
              d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
              clip-rule="evenodd" />
      </svg>
      <svg xmlns="http://www.w3.org/2000/svg"
           class="h-5 w-5 text-gray-500 dark:text-gray-400"
           viewBox="0 0 20 20"
           fill="currentColor"
           aria-hidden="true">
        <path fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM4.332 8.027a6.012 6.012 0 011.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 019 7.5V8a2 2 0 004 0 2 2 0 011.523-1.943A5.977 5.977 0 0116 10c0 .34-.028.675-.083 1H15a2 2 0 00-2 2v2.197A5.973 5.973 0 0110 16v-2a2 2 0 00-2-2 2 2 0 01-2-2 2 2 0 00-1.668-1.973z"
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
        <li v-for="jurisdiction in jurisdictions"
            :key="jurisdiction"
            @click="selectJurisdiction(jurisdiction)"
            class="relative py-2 pl-3 pr-9 cursor-default select-none font-brand text-base
                 hover:bg-brand-100 dark:hover:bg-brand-600 transition-colors duration-200"
            :class="{ 'bg-brand-50 dark:bg-brand-500': selectedJurisdiction === jurisdiction }"
            role="option"
            :aria-selected="selectedJurisdiction === jurisdiction">
          <span class="block truncate"
                :class="{ 'font-semibold': selectedJurisdiction === jurisdiction }">
            {{ jurisdiction }}
          </span>
          <span v-if="selectedJurisdiction === jurisdiction"
                class="absolute inset-y-0 right-0 flex items-center pr-4 text-brand-600
                   dark:text-brand-300">
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
        </li>
      </ul>
    </transition>
  </div>
</template>


<script setup lang="ts">
import { ref } from 'vue';

const jurisdictions = ['EU', 'US', 'Asia'];
const selectedJurisdiction = ref('EU');
const isOpen = ref(false);

const selectJurisdiction = (jurisdiction: string) => {
  selectedJurisdiction.value = jurisdiction;
  isOpen.value = false;
  // You can emit an event here if you need to inform the parent component
  // emit('jurisdictionChanged', jurisdiction);
};

const toggleDropdown = () => {
  isOpen.value = !isOpen.value;
};
</script>
