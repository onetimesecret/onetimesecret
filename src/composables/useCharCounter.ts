// src/composables/useCharCounter.ts

import { ref } from 'vue';

export function useCharCounter() {
  const isHovering = ref(false);

  const handleMouseEnter = () => (isHovering.value = true);
  const handleMouseLeave = () => (isHovering.value = false);

  const formatNumber = (num: number) => new Intl.NumberFormat().format(num);

  return {
    isHovering,
    handleMouseEnter,
    handleMouseLeave,
    formatNumber,
  };
}
