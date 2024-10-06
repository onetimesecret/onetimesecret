<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
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
const dropdownRef = ref<HTMLElement | null>(null);

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


const isCollapsed = ref(true);
const isHovered = ref(false);

const toggleCollapse = (event: Event) => {
  event.stopPropagation();
  isCollapsed.value = !isCollapsed.value;
  if (!isCollapsed.value) {
    isOpen.value = true;
  } else {
    isOpen.value = false;
  }
};

const handleMouseEnter = () => {
  isHovered.value = true;
};

const handleMouseLeave = () => {
  isHovered.value = false;
};

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
    <textarea class="w-full h-48 p-3 border border-gray-300 rounded-md focus:ring-brandcompdim-500 focus:border-brandcompdim-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
              name="secret"
              autofocus
              autocomplete="off"
              placeholder="Secret content goes here..."
              aria-label="Enter the secret content here"></textarea>
    <div class="absolute bottom-4 right-2 transition-opacity duration-200"
         :class="{ 'opacity-50': !isHovered && isCollapsed }"
         @mouseenter="handleMouseEnter"
         @mouseleave="handleMouseLeave">
      <div class="relative inline-block text-left"
           ref="dropdownRef">
        <button type="button"
                class="inline-flex justify-center items-center rounded-full border border-gray-300 dark:border-gray-600 shadow-sm p-2 bg-white text-sm font-medium text-gray-700 dark:bg-gray-800 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 dark:focus:ring-offset-gray-800"
                @click="toggleCollapse"
                :aria-expanded="!isCollapsed"
                aria-haspopup="true">
          <Icon icon="heroicons-solid:cog"
                class="h-5 w-5 text-gray-400 dark:text-gray-500"
                aria-hidden="true" />
        </button>

        <transition enter-active-class="transition ease-out duration-100"
                    enter-from-class="transform opacity-0 scale-95"
                    enter-to-class="transform opacity-100 scale-100"
                    leave-active-class="transition ease-in duration-75"
                    leave-from-class="transform opacity-100 scale-100"
                    leave-to-class="transform opacity-0 scale-95">
          <div v-if="isOpen && !isCollapsed"
               class="absolute right-0 mt-2 w-56 rounded-md shadow-lg bg-white dark:bg-gray-800 ring-1 ring-black ring-opacity-5 dark:ring-gray-700 focus:outline-none z-50 max-h-60 overflow-y-auto break-words">
            <div class="py-1"
                 role="menu"
                 aria-orientation="vertical"
                 aria-labelledby="options-menu">
              <div class="px-4 py-2 text-sm font-brand text-gray-700 dark:text-gray-300 font-semibold">
                Select Domain
              </div>
              <a v-for="domain in availableDomains"
                 :key="domain"
                 href="#"
                 class="block px-4 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-white whitespace-normal break-words"
                 role="menuitem"
                 @click.stop="selectDomain(domain)">
                {{ domain }}
              </a>
            </div>
          </div>
        </transition>
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
