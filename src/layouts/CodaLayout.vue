<!-- src/layouts/CodaLayout.vue -->
<!--
  Coda Layout - Claude Code Inspired Split View

  Features:
  - Desktop: Fixed sidebar (350-400px) + content area
  - Mobile: Single column with toggleable sidebar
  - Dark theme optimized
  - Full height layout with proper scrolling
-->

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';

interface Props {
  showSidebar?: boolean;
  sidebarWidth?: string;
}

interface Emits {
  (e: 'toggle-sidebar'): void;
}

const { showSidebar, sidebarWidth } = withDefaults(defineProps<Props>(), {
  showSidebar: true,
  sidebarWidth: '480px',
});

const emit = defineEmits<Emits>();

const isMobile = ref(false);

const checkMobile = () => {
  isMobile.value = window.innerWidth < 768;
};

onMounted(() => {
  checkMobile();
  window.addEventListener('resize', checkMobile);
});

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile);
});

const handleToggleSidebar = () => {
  emit('toggle-sidebar');
};
</script>

<template>
  <div class="h-screen w-full bg-gray-900 flex overflow-hidden">
    <!-- Sidebar -->
    <aside
      v-if="showSidebar || !isMobile"
      :class="[
        'transition-transform duration-300 ease-in-out shrink-0',
        'border-r border-gray-700',
        isMobile
          ? 'fixed inset-y-0 left-0 z-40 w-full bg-gray-900'
          : 'relative',
        !isMobile && 'hidden md:block'
      ]"
      :style="!isMobile ? { width: sidebarWidth } : {}"
    >
      <slot name="sidebar" ></slot>
    </aside>

    <!-- Mobile sidebar backdrop -->
    <div
      v-if="isMobile && showSidebar"
      class="fixed inset-0 bg-black/50 z-30 md:hidden"
      @click="handleToggleSidebar"
    ></div>

    <!-- Main Content Area -->
    <main
      :class="[
        'flex-1 overflow-hidden',
        isMobile && showSidebar ? 'hidden' : 'flex flex-col'
      ]"
    >
      <slot ></slot>
    </main>
  </div>
</template>

<style scoped>
/* Ensure full height layout */
:deep(.h-screen) {
  height: 100vh;
  height: 100dvh; /* Dynamic viewport height for mobile browsers */
}
</style>
