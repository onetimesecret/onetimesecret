<!-- src/components/DropdownToggle.vue -->
<template>
  <div class="flex items-center relative"
       :class="{ 'opacity-60 hover:opacity-100': !isMenuOpen }"
       :aria-label="ariaLabel">
    <button type="button"
            class="inline-flex items-center justify-center w-full rounded-md border
           border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2 bg-white dark:bg-gray-800 text-sm font-medium
           text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700
           focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-gray-100 dark:focus:ring-offset-gray-900"
            :aria-expanded="isMenuOpen"
            aria-haspopup="true"
            @click="toggleMenu"
            @keydown.down.prevent="openMenu"
            @keydown.enter.prevent="openMenu"
            @keydown.space.prevent="openMenu">
      <slot name="button-content"></slot>
      <svg class="ml-2 -mr-1 h-5 w-5"
           xmlns="http://www.w3.org/2000/svg"
           viewBox="0 0 20 20"
           fill="currentColor"
           aria-hidden="true">
        <path fill-rule="evenodd"
              d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
              clip-rule="evenodd" />
      </svg>
    </button>

    <div v-if="isMenuOpen"
         class="absolute right-0 bottom-full mb-2 w-56 rounded-md shadow-lg
           bg-white dark:bg-gray-800 ring-1 ring-black ring-opacity-5
           dark:ring-white dark:ring-opacity-20 focus:outline-none z-[100]"
         role="menu"
         aria-orientation="vertical"
         @keydown.esc="closeMenu"
         @keydown.up.prevent="focusPreviousItem"
         @keydown.down.prevent="focusNextItem">
      <div class="py-1 max-h-60 overflow-y-auto"
           role="none">
        <slot name="menu-items"></slot>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';

defineProps<{
  ariaLabel: string;
}>();


const emit = defineEmits(['menuToggled']);

const isMenuOpen = ref(false);
const menuItems = ref<HTMLElement[]>([]);

const toggleMenu = () => {
  isMenuOpen.value = !isMenuOpen.value;
  emit('menuToggled', isMenuOpen.value);
};

const openMenu = () => {
  isMenuOpen.value = true;
  emit('menuToggled', isMenuOpen.value);
};

const closeMenu = () => {
  isMenuOpen.value = false;
  emit('menuToggled', isMenuOpen.value);
};

const focusNextItem = () => {
  const currentIndex = menuItems.value.indexOf(document.activeElement as HTMLElement);
  const nextIndex = (currentIndex + 1) % menuItems.value.length;
  menuItems.value[nextIndex].focus();
};

const focusPreviousItem = () => {
  const currentIndex = menuItems.value.indexOf(document.activeElement as HTMLElement);
  const previousIndex = (currentIndex - 1 + menuItems.value.length) % menuItems.value.length;
  menuItems.value[previousIndex].focus();
};

const handleClickOutside = (event: MouseEvent) => {
  const target = event.target as HTMLElement;
  if (!target.closest('.relative')) {
    closeMenu();
  }
};

const handleEscapeKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeMenu();
  }
};

onMounted(() => {
  menuItems.value = Array.from(document.querySelectorAll('[role="menuitem"]')) as HTMLElement[];

  document.addEventListener('click', handleClickOutside);
  document.addEventListener('keydown', handleEscapeKey);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
  document.removeEventListener('keydown', handleEscapeKey);
});


// Expose methods to parent component
defineExpose({ closeMenu });
</script>
