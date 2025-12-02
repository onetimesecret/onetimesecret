// src/composables/useDropdown.ts

import { onMounted, onUnmounted, ref } from 'vue';

export function useDropdown() {
  const isOpen = ref(false);
  const dropdownRef = ref<HTMLElement | null>(null);

  const toggle = (event: Event) => {
    event.stopPropagation();
    isOpen.value = !isOpen.value;
  };

  const close = () => {
    isOpen.value = false;
  };

  onMounted(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.value && !dropdownRef.value.contains(event.target as Node)) {
        close();
      }
    };

    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close();
    };

    document.addEventListener('click', handleClickOutside);
    document.addEventListener('keydown', handleEscape);

    onUnmounted(() => {
      document.removeEventListener('click', handleClickOutside);
      document.removeEventListener('keydown', handleEscape);
    });
  });

  return {
    isOpen,
    dropdownRef,
    toggle,
    close,
  };
}
