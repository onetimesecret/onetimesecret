<!-- src/components/navigation/CodaSidebar.vue -->
<!--
  Coda Sidebar Component

  Displays a session/item list inspired by Claude Code's sidebar:
  - Session cards with title, subtitle, timestamp
  - Active state highlighting
  - Hover states
  - Filter/search capabilities
-->

<script setup lang="ts">
import { ref, computed } from 'vue';

interface Session {
  id: string;
  title: string;
  subtitle: string;
  timestamp: string;
  isActive?: boolean;
}

interface Props {
  sessions: Session[];
  activeSessionId: string;
}

interface Emits {
  (e: 'select-session', id: string): void;
}

const props = defineProps<Props>();
const emit = defineEmits<Emits>();

const filterQuery = ref('');

const filteredSessions = computed(() => {
  if (!filterQuery.value) {
    return props.sessions;
  }

  const query = filterQuery.value.toLowerCase();
  return props.sessions.filter(
    session =>
      session.title.toLowerCase().includes(query) ||
      session.subtitle.toLowerCase().includes(query)
  );
});

const handleSelectSession = (id: string) => {
  emit('select-session', id);
};
</script>

<template>
  <div class="h-full flex flex-col bg-gray-900">
    <!-- Sidebar Header -->
    <div class="p-4 border-b border-gray-700">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-white font-semibold text-xl">OneTime Secret</h2>
      </div>

      <!-- Search Input -->
      <div class="relative">
        <input
          v-model="filterQuery"
          type="text"
          placeholder="Search secrets..."
          class="w-full px-3 py-2.5 bg-gray-800 border border-gray-700 rounded-lg
                 text-gray-300 text-sm placeholder-gray-500
                 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent"
        />
        <button
          class="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 bg-brand-500 hover:bg-brand-600 rounded text-white"
          aria-label="Create new secret"
        >
          <svg class="w-4 h-4"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
            <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Sessions List -->
    <div class="flex-1 overflow-y-auto">
      <div class="px-4 py-3 flex items-center justify-between">
        <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider">Recent Secrets</h3>
        <button class="text-xs text-gray-500 hover:text-gray-400 flex items-center gap-1">
          <span>All</span>
          <svg class="w-3 h-3"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
            <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      <div class="space-y-1 px-2 pb-4">
        <button
          v-for="session in filteredSessions"
          :key="session.id"
          @click="handleSelectSession(session.id)"
          :class="[
            'w-full text-left px-3 py-3 rounded-lg transition-colors relative',
            session.id === activeSessionId
              ? 'bg-gray-800 border border-gray-700'
              : 'hover:bg-gray-800/50'
          ]"
        >
          <!-- Active indicator -->
          <div
            v-if="session.id === activeSessionId"
            class="absolute right-3 top-1/2 -translate-y-1/2"
          >
            <svg class="w-4 h-4 text-orange-500"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
              <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M5 13l4 4L19 7" />
            </svg>
          </div>

          <div class="pr-6">
            <div class="text-sm font-medium text-white mb-0.5 line-clamp-2">
              {{ session.title }}
            </div>
            <div class="text-xs text-gray-500">
              {{ session.subtitle }}
            </div>
          </div>
        </button>
      </div>
    </div>

    <!-- Sidebar Footer -->
    <div class="hidden md:flex border-t border-gray-700 p-4">
      <button
        class="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-800 hover:bg-gray-750 rounded-lg text-gray-300 hover:text-white transition-colors"
        aria-label="Account settings"
      >
        <svg class="w-5 h-5"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
          <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
        </svg>
        <span class="text-sm font-medium">Account</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
/* Custom scrollbar for dark theme */
.overflow-y-auto::-webkit-scrollbar {
  width: 6px;
}

.overflow-y-auto::-webkit-scrollbar-track {
  background: transparent;
}

.overflow-y-auto::-webkit-scrollbar-thumb {
  background: #374151;
  border-radius: 3px;
}

.overflow-y-auto::-webkit-scrollbar-thumb:hover {
  background: #4b5563;
}
</style>
