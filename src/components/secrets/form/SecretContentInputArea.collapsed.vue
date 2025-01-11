<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { ref, onMounted, onUnmounted } from 'vue';

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
    <textarea
      class="h-32 w-full rounded-md border border-gray-300 p-3 focus:border-brandcompdim-500 focus:ring-brandcompdim-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
      name="secret"
      autofocus
      autocomplete="off"
      :placeholder="$t('web.COMMON.secret_placeholder')"
      aria-label="Enter the secret content here"></textarea>

    <div
      class="absolute bottom-2 right-2 transition-opacity duration-200"
      :class="{ 'opacity-50': !isHovered && isCollapsed }"
      @mouseenter="handleMouseEnter"
      @mouseleave="handleMouseLeave">
      <div
        class="relative inline-block text-left"
        ref="dropdownRef">
        <button
          type="button"
          class="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-3 py-1 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 dark:focus:ring-offset-gray-800"
          @click="toggleCollapse">
          <span
            v-if="!isCollapsed"
            class="max-w-[150px] truncate text-sm font-bold text-brandcomp-600 dark:text-brandcomp-400">
            {{ selectedDomain || 'Select Domain' }}
          </span>
          <OIcon
            collection="heroicons"
            :name="isCollapsed ? 'heroicons-solid:chevron-down' : 'heroicons-solid:chevron-left'"
            class="size-4 text-gray-400 dark:text-gray-500"
            aria-hidden="true"
          />
        </button>

        <transition
          enter-active-class="transition ease-out duration-100"
          enter-from-class="transform opacity-0 scale-95"
          enter-to-class="transform opacity-100 scale-100"
          leave-active-class="transition ease-in duration-75"
          leave-from-class="transform opacity-100 scale-100"
          leave-to-class="transform opacity-0 scale-95">
          <div
            v-if="isOpen && !isCollapsed"
            class="absolute right-0 z-50 mt-2 max-h-60 w-56 overflow-y-auto break-words rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700">
            <div
              class="py-1"
              role="menu"
              aria-orientation="vertical"
              aria-labelledby="options-menu">
              <a
                v-for="domain in availableDomains"
                :key="domain"
                href="#"
                class="block whitespace-normal break-words px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white"
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
