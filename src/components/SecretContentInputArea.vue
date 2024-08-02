<script setup lang="ts">
import { ref } from 'vue';
import { Icon } from '@iconify/vue';

interface Props {
  availableDomains: string[];
  initialDomain?: string;
}

const props = withDefaults(defineProps<Props>(), {
  initialDomain: '',
});

const emit = defineEmits(['update:selectedDomain']);

const isOpen = ref(false);
const selectedDomain = ref(props.initialDomain);

const toggleDropdown = () => {
  isOpen.value = !isOpen.value;
};

const selectDomain = (domain: string) => {
  selectedDomain.value = domain;
  emit('update:selectedDomain', domain);
  isOpen.value = false;
};
</script>

<template>
  <div class="relative">
    <textarea class="w-full h-32 p-3
        border border-gray-300 rounded-md
        focus:ring-brandcompdim-500 focus:border-brandcompdim-500
        dark:bg-gray-700 dark:border-gray-600 dark:text-white"
      name="secret"
      autofocus
      autocomplete="off"
      placeholder="Secret content goes here..."
      aria-label="Enter the secret content here"></textarea>
    <div class="absolute top-2 right-2">
      <!--
        Dropdown Sizing Guide:
        1. Button size: Adjust px-4 py-2 in the button class
        2. Button text: Change text-base for larger/smaller font
        3. Dropdown icon: Modify h-5 w-5 to change icon size
        4. Dropdown menu:
            - Change w-64 to adjust menu width
            - Modify py-3 in menu items for height
            - Adjust text-base in menu items for font size
        Increase/decrease these values as needed for desired size.
        -->
      <div class="relative inline-block text-left">
        <div>
          <button type="button"
                  class="inline-flex justify-center items-center w-full rounded-md
                  border border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2
                  bg-white text-lg font-medium text-gray-700
                  dark:bg-gray-800 dark:text-gray-300
                  hover:bg-gray-50 dark:hover:bg-gray-700
                  focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 dark:focus:ring-offset-gray-800"
                  @click="toggleDropdown">
            <span
                  class="text-base text-brandcomp-600 dark:text-brandcomp-400 font-bold">
                  {{ selectedDomain || 'Select Domain' }}
            </span>
            <Icon icon="heroicons-solid:chevron-down"
                  class="ml-2 -mr-1 h-5 w-5 text-gray-400 dark:text-gray-500"
                  aria-hidden="true" />
          </button>
        </div>

        <div v-if="isOpen"
             class="origin-top-right absolute right-0 mt-2 w-64 rounded-md shadow-lg
              bg-white dark:bg-gray-800
              ring-1 ring-black ring-opacity-5 dark:ring-gray-700
              focus:outline-none z-50">
          <div class="py-1"
               role="menu"
               aria-orientation="vertical"
               aria-labelledby="options-menu">
            <a v-for="domain in availableDomains"
               :key="domain"
               href="#"
               class="block px-4 py-3 text-base
                text-gray-700 dark:text-gray-300
                hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-white"
               role="menuitem"
               @click.prevent="selectDomain(domain)">
              {{ domain }}
            </a>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>


<style scoped>
/* Ensure the dropdown container has a higher z-index than the input field */
.absolute {
  z-index: 400;
}
</style>
