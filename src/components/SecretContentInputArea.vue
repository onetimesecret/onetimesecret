<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { Icon } from '@iconify/vue';

interface Props {
  availableDomains?: string[];
  initialDomain?: string;
  withDomainDropdown?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  initialDomain: '',
  withDomainDropdown: false,
});

const emit = defineEmits(['update:selectedDomain', 'update:content']);

const content = ref('');

watch(content, (newContent) => {
  emit('update:content', newContent);
});

const isOpen = ref(false);
const selectedDomain = ref(props.initialDomain);
const dropdownRef = ref<HTMLElement | null>(null);

const toggleDropdown = (event: Event) => {
  event.stopPropagation(); // Stop the event from propagating to the document
  isOpen.value = !isOpen.value;
};

const selectDomain = (domain: string) => {
  selectedDomain.value = domain;
  emit('update:selectedDomain', domain);
  isOpen.value = false;
};

const closeDropdown = () => {
  isOpen.value = false;
};

const handleClickOutside = (event: MouseEvent) => {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target as Node)) {
    closeDropdown();
  }
};

const handleEscapeKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeDropdown();
  }
};

onMounted(() => {
  document.addEventListener('click', handleClickOutside);
  document.addEventListener('keydown', handleEscapeKey);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
  document.removeEventListener('keydown', handleEscapeKey);
});

</script>

<!--

  FEATURE: Closing dropdown on click outside or Escape key press

  1. Added `ref="dropdownRef"` to the dropdown container div.
  2. Created a `closeDropdown` function to close the dropdown.
  3. Added `handleClickOutside` function to check if a click occurred outside the dropdown.
  4. Added `handleEscapeKey` function to close the dropdown when the Escape key is pressed.
  5. Set up event listeners in the `onMounted` hook and removed them in the `onUnmounted` hook.

  These changes will make the dropdown close when clicking outside of it or pressing the
  Escape key. The click outside functionality checks if the click target is not contained
  within the dropdown element, and if so, it closes the dropdown. The Escape key
  functionality simply closes the dropdown when the key is pressed.

  -->

<template>
  <div class="relative">
    <textarea ref="secretContentRef" tabindex="1"
              v-model="content"
              class="w-full h-40 p-3 font-mono
                border border-gray-300 rounded-md
              focus:ring-brandcompdim-500 focus:border-brandcompdim-500
              dark:bg-gray-700 dark:border-gray-600 dark:text-white"
              name="secret"
              autofocus
              autocomplete="off"
              placeholder="Secret content goes here..."
              aria-label="Enter the secret content to share here"></textarea>

    <div v-if="withDomainDropdown" class="absolute bottom-4 right-2">
      <div class="relative inline-block text-left"
           ref="dropdownRef">
        <div>
          <button type="button" tabindex="2"
                  class="inline-flex justify-center items-center w-full rounded-md
                  pl-4 py-2
                  border border-gray-300 dark:border-gray-600 shadow-sm
                  bg-white text-lg font-medium text-gray-700
                  dark:bg-gray-800 dark:text-gray-300
                  hover:bg-gray-50 dark:hover:bg-gray-700
                  focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 dark:focus:ring-offset-gray-800"
                  @click="toggleDropdown">

            <span class="text-base text-brandcomp-600 dark:text-brandcomp-400 font-bold truncate max-w-[200px]">
              {{ selectedDomain || 'Select Domain' }}
            </span>
            <Icon icon="heroicons-solid:chevron-down"
                  class="ml-2 flex-shrink-0 h-5 w-5 text-gray-400 dark:text-gray-500"
                  aria-hidden="true" />
          </button>
        </div>

        <!-- -class="origin-bottom-right absolute bottom-full right-0 mb-2 mt-2 w-64 rounded-md shadow-lg" -->
        <div v-if="isOpen"
             class="origin-top-right absolute right-0 mt-2 w-64 rounded-md shadow-lg
              bg-white dark:bg-gray-800
              ring-1 ring-black ring-opacity-5 dark:ring-gray-700
              focus:outline-none z-50
              max-h-60 overflow-y-auto break-words">
          <div class="py-1"
               role="menu"
               aria-orientation="vertical"
               aria-labelledby="options-menu">
            <a v-for="domain in availableDomains"
               :key="domain"
               href="#"
               class="block px-5 py-3 text-base
                text-gray-700 dark:text-gray-300
                hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-white
                whitespace-normal break-words"
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
  z-index: 40;
}
</style>
