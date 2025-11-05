<!-- src/views/demo/NavigationCodaDemo.vue -->
<!--
  Navigation Coda Demo - Claude Code Inspired Layout

  Demonstrates a split-view layout inspired by Claude Code's interface:
  - Left sidebar with sessions/items list (350-400px)
  - Right panel with full content area
  - Mobile collapses to single view with back navigation
  - Dark theme optimized
-->

<script setup lang="ts">
import { ref, computed } from 'vue';
import CodaLayout from '@/layouts/CodaLayout.vue';
import CodaSidebar from '@/components/navigation/CodaSidebar.vue';

// Demo data - represents secrets/sessions
interface Session {
  id: string;
  title: string;
  subtitle: string;
  timestamp: string;
  isActive?: boolean;
}

const sessions = ref<Session[]>([
  {
    id: '1',
    title: 'Production API credentials for deploy',
    subtitle: 'onetimesecret/production',
    timestamp: '2 minutes ago',
    isActive: true,
  },
  {
    id: '2',
    title: 'Database migration password',
    subtitle: 'onetimesecret/staging',
    timestamp: '1 hour ago',
  },
  {
    id: '3',
    title: 'SSH key for backup server',
    subtitle: 'infrastructure/backup',
    timestamp: '3 hours ago',
  },
  {
    id: '4',
    title: 'Temporary access token for vendor',
    subtitle: 'onetimesecret/integrations',
    timestamp: 'Yesterday',
  },
  {
    id: '5',
    title: 'Client credentials for demo',
    subtitle: 'clients/acme-corp',
    timestamp: '2 days ago',
  },
  {
    id: '6',
    title: 'Emergency access codes',
    subtitle: 'onetimesecret/security',
    timestamp: 'Last week',
  },
]);

const activeSessionId = ref('1');
const showMobileSidebar = ref(true);

const activeSession = computed(() => sessions.value.find(s => s.id === activeSessionId.value));

const selectSession = (id: string) => {
  activeSessionId.value = id;
  // On mobile, hide sidebar when selecting a session
  if (window.innerWidth < 768) {
    showMobileSidebar.value = false;
  }
};

const toggleMobileSidebar = () => {
  showMobileSidebar.value = !showMobileSidebar.value;
};
</script>

<template>
  <CodaLayout
    :show-sidebar="showMobileSidebar"
    @toggle-sidebar="toggleMobileSidebar"
  >
    <!-- Sidebar Content -->
    <template #sidebar>
      <CodaSidebar
        :sessions="sessions"
        :active-session-id="activeSessionId"
        @select-session="selectSession"
      />
    </template>

    <!-- Main Content -->
    <template #default>
      <div class="h-full flex flex-col">
        <!-- Mobile header with back button -->
        <div class="md:hidden sticky top-0 z-10 bg-gray-900 border-b border-gray-700 px-4 py-3 flex items-center gap-3">
          <button
            @click="toggleMobileSidebar"
            class="text-gray-400 hover:text-white"
            aria-label="Show secrets list"
          >
            <svg class="w-5 h-5"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
              <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <h1 class="text-sm font-medium text-white truncate">
            {{ activeSession?.title }}
          </h1>
        </div>

        <!-- Desktop header -->
        <div class="hidden md:flex items-center justify-between border-b border-gray-700 px-8 py-4 bg-gray-900/50">
          <div class="flex items-center gap-3">
            <h1 class="text-xl font-semibold text-white">
              {{ activeSession?.title }}
            </h1>
          </div>
          <div class="text-xs text-gray-500">{{ activeSession?.subtitle }}</div>
        </div>

        <!-- Content Area -->
        <div class="flex-1 overflow-y-auto p-8 space-y-6 max-w-5xl">
          <!-- Secret Details Card -->
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div class="flex items-start justify-between mb-4">
              <div>
                <h2 class="text-lg font-semibold text-white mb-2">
                  {{ activeSession?.title }}
                </h2>
                <p class="text-sm text-gray-400">{{ activeSession?.subtitle }}</p>
              </div>
              <span class="px-3 py-1 bg-green-900/30 text-green-400 text-xs rounded-full border border-green-800">
                Active
              </span>
            </div>

            <div class="grid grid-cols-2 gap-4 mb-4">
              <div>
                <div class="text-xs text-gray-500 mb-1">Created</div>
                <div class="text-sm text-gray-300">{{ activeSession?.timestamp }}</div>
              </div>
              <div>
                <div class="text-xs text-gray-500 mb-1">Expires</div>
                <div class="text-sm text-gray-300">In 7 days</div>
              </div>
              <div>
                <div class="text-xs text-gray-500 mb-1">Views Remaining</div>
                <div class="text-sm text-gray-300">1 of 1</div>
              </div>
              <div>
                <div class="text-xs text-gray-500 mb-1">Secret Key</div>
                <div class="text-sm font-mono text-gray-300">abc123xyz789</div>
              </div>
            </div>

            <div class="flex gap-3">
              <button class="px-4 py-2 bg-brand-500 hover:bg-brand-600 text-white rounded-lg text-sm font-medium">
                View Secret
              </button>
              <button class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg text-sm font-medium">
                Copy Link
              </button>
              <button class="px-4 py-2 bg-red-900/30 hover:bg-red-900/50 text-red-400 rounded-lg text-sm font-medium border border-red-800">
                Burn Secret
              </button>
            </div>
          </div>

          <!-- Activity Feed -->
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <h3 class="text-sm font-semibold text-white mb-4">Recent Activity</h3>
            <div class="space-y-3">
              <div class="flex items-start gap-3">
                <div class="w-2 h-2 rounded-full bg-green-500 mt-1.5"></div>
                <div class="flex-1">
                  <div class="text-sm text-gray-300">Secret created</div>
                  <div class="text-xs text-gray-500">{{ activeSession?.timestamp }}</div>
                </div>
              </div>
              <div class="flex items-start gap-3">
                <div class="w-2 h-2 rounded-full bg-blue-500 mt-1.5"></div>
                <div class="flex-1">
                  <div class="text-sm text-gray-300">Link copied to clipboard</div>
                  <div class="text-xs text-gray-500">{{ activeSession?.timestamp }}</div>
                </div>
              </div>
            </div>
          </div>

          <!-- Demo controls -->
          <div class="mt-8 p-6 bg-blue-900/20 rounded-lg border border-blue-800">
            <h2 class="text-lg font-semibold text-white mb-3">Split-View Layout Demo</h2>
            <p class="text-sm text-gray-400 mb-4">
              This alternate design showcases a wider split-view layout with persistent sidebar
              for managing multiple secrets and responsive mobile behavior.
            </p>

            <div class="grid md:grid-cols-2 gap-4 text-sm">
              <div>
                <h3 class="font-medium text-white mb-2">Desktop Features</h3>
                <ul class="space-y-1 text-gray-400">
                  <li>• Wide split view (480px sidebar + content)</li>
                  <li>• Persistent secrets list</li>
                  <li>• Dark theme with brand accents</li>
                  <li>• Quick actions and metadata</li>
                </ul>
              </div>
              <div>
                <h3 class="font-medium text-white mb-2">Mobile Features</h3>
                <ul class="space-y-1 text-gray-400">
                  <li>• Full-screen sidebar overlay</li>
                  <li>• Back navigation to secrets list</li>
                  <li>• Bottom action bar</li>
                  <li>• Touch-optimized interface</li>
                </ul>
              </div>
            </div>

            <div class="mt-4 pt-4 border-t border-blue-800">
              <h3 class="font-medium text-white mb-2">Try It</h3>
              <ul class="space-y-1 text-sm text-gray-400">
                <li>• Click different secrets in sidebar to switch between them</li>
                <li>• Resize browser window to see responsive behavior</li>
                <li>• On mobile, use back button to return to secrets list</li>
              </ul>
            </div>
          </div>

          <!-- Key improvements -->
          <div class="grid md:grid-cols-2 gap-4">
            <div class="bg-green-900/20 rounded-lg p-4 border border-green-800">
              <h3 class="font-semibold text-green-100 mb-2">✅ Design Approach</h3>
              <ul class="space-y-1 text-sm text-green-200">
                <li>• Wider layout for more breathing room</li>
                <li>• Secret-focused navigation</li>
                <li>• Dark theme with brand colors</li>
                <li>• Clear action hierarchy</li>
                <li>• Quick access to common operations</li>
              </ul>
            </div>

            <div class="bg-purple-900/20 rounded-lg p-4 border border-purple-800">
              <h3 class="font-semibold text-purple-100 mb-2">🎯 Use Cases</h3>
              <ul class="space-y-1 text-sm text-purple-200">
                <li>• Managing multiple active secrets</li>
                <li>• Quick comparison between secrets</li>
                <li>• Batch operations workflow</li>
                <li>• Power user dashboard</li>
                <li>• Team secret management</li>
              </ul>
            </div>
          </div>
        </div>

        <!-- Bottom action bar (mobile) -->
        <div class="md:hidden border-t border-gray-700 bg-gray-900">
          <div class="flex items-center justify-around p-3">
            <button class="flex flex-col items-center gap-1 text-gray-400 hover:text-white">
              <svg class="w-6 h-6"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
                <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M12 4v16m8-8H4" />
              </svg>
              <span class="text-xs">New</span>
            </button>
            <button class="flex flex-col items-center gap-1 text-gray-400 hover:text-white">
              <svg class="w-6 h-6"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
                <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span class="text-xs">Recent</span>
            </button>
            <button class="flex flex-col items-center gap-1 text-gray-400 hover:text-white">
              <svg class="w-6 h-6"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
                <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
              </svg>
              <span class="text-xs">Account</span>
            </button>
          </div>
        </div>
      </div>
    </template>
  </CodaLayout>
</template>
