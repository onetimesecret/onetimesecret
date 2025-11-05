<!-- src/views/demo/TeamNavigationDemo.vue -->
<!--
  Team & Notifications Navigation Demo

  This demonstrates how team features and notifications integrate
  into the improved navigation system.
-->

<script setup lang="ts">
import { ref, computed } from 'vue';

// Demo data
const currentTeam = ref({
  id: 'team-1',
  name: 'Acme Corp',
  role: 'admin',
  members: 12,
});

const teams = ref([
  { id: 'personal', name: 'Personal', role: 'owner', members: 1 },
  { id: 'team-1', name: 'Acme Corp', role: 'admin', members: 12 },
  { id: 'team-2', name: 'StartupCo', role: 'member', members: 5 },
]);

const notifications = ref([
  { id: 1, type: 'share', message: 'John shared a secret with you', time: '2 min ago', unread: true },
  { id: 2, type: 'team', message: 'Sarah joined Acme Corp', time: '1 hour ago', unread: true },
  { id: 3, type: 'expire', message: 'Secret "API Keys" expired', time: '3 hours ago', unread: false },
]);

const unreadCount = computed(() => notifications.value.filter(n => n.unread).length);

const showTeamSwitcher = ref(false);
const showNotifications = ref(false);

// Navigation items with team context
const navItems = computed(() => {
  const items = [
    { id: 'dashboard', label: 'Dashboard', path: '/dashboard', icon: 'squares-2x2' },
    { id: 'secrets', label: 'My Secrets', path: '/secrets', icon: 'key', count: 23 },
  ];

  // Add team-specific items when in team context
  if (currentTeam.value.id !== 'personal') {
    items.push(
      { id: 'team-secrets', label: 'Team Secrets', path: '/team/secrets', icon: 'users', count: 47 },
      { id: 'members', label: 'Members', path: '/team/members', icon: 'user-group', count: currentTeam.value.members }
    );
  }

  items.push(
    { id: 'domains', label: 'Domains', path: '/domains', icon: 'globe', count: 3 },
    { id: 'api', label: 'API', path: '/api', icon: 'code-bracket' },
    { id: 'settings', label: 'Settings', path: '/settings', icon: 'cog' }
  );

  return items;
});

const toggleTeamSwitcher = () => {
  showTeamSwitcher.value = !showTeamSwitcher.value;
  showNotifications.value = false;
};

const toggleNotifications = () => {
  showNotifications.value = !showNotifications.value;
  showTeamSwitcher.value = false;
};

const switchTeam = (teamId: string) => {
  const team = teams.value.find(t => t.id === teamId);
  if (team) {
    currentTeam.value = team;
    showTeamSwitcher.value = false;
  }
};

const markAllRead = () => {
  notifications.value.forEach(n => n.unread = false);
};
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Enhanced Header with Team & Notifications -->
    <header class="bg-white border-b border-gray-200 dark:bg-gray-900 dark:border-gray-800">
      <div class="container mx-auto max-w-7xl px-4">
        <div class="flex items-center justify-between h-16">
          <!-- Left: Logo + Team Switcher -->
          <div class="flex items-center gap-4">
            <!-- Logo -->
            <div class="flex items-center gap-2">
              <div class="size-8 bg-brand-500 rounded-lg flex items-center justify-center text-white font-bold">
                OT
              </div>
              <span class="font-bold text-lg hidden sm:block">OneTime</span>
            </div>

            <!-- Team Switcher -->
            <div class="relative">
              <button
                @click="toggleTeamSwitcher"
                class="flex items-center gap-2 px-3 py-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors">
                <span class="font-medium">{{ currentTeam.name }}</span>
                <svg class="size-4 text-gray-500"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
                  <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M19 9l-7 7-7-7" />
                </svg>
              </button>

              <!-- Team Dropdown -->
              <div
                v-if="showTeamSwitcher"
                class="absolute top-full left-0 mt-2 w-64 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-50">
                <div class="p-2">
                  <div class="text-xs font-medium text-gray-500 dark:text-gray-400 px-3 py-2">
                    Switch Team/Account
                  </div>
                  <button
                    v-for="team in teams"
                    :key="team.id"
                    @click="switchTeam(team.id)"
                    class="w-full flex items-center justify-between px-3 py-2 rounded hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                    :class="{ 'bg-brand-50 dark:bg-brand-900/20': team.id === currentTeam.id }">
                    <div class="flex items-center gap-3">
                      <div class="size-8 bg-gray-200 dark:bg-gray-600 rounded-full flex items-center justify-center text-xs font-medium">
                        {{ team.name.substring(0, 2).toUpperCase() }}
                      </div>
                      <div class="text-left">
                        <div class="font-medium">{{ team.name }}</div>
                        <div class="text-xs text-gray-500">{{ team.members }} members</div>
                      </div>
                    </div>
                    <span v-if="team.id === currentTeam.id" class="text-brand-500">✓</span>
                  </button>
                  <div class="border-t border-gray-200 dark:border-gray-700 mt-2 pt-2">
                    <button class="w-full px-3 py-2 text-left text-brand-600 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors">
                      + Create new team
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Right: Notifications + User Menu -->
          <div class="flex items-center gap-3">
            <!-- Quick Create Button -->
            <button class="px-4 py-2 bg-brand-500 text-white rounded-lg hover:bg-brand-600 transition-colors text-sm font-medium">
              + New Secret
            </button>

            <!-- Notifications -->
            <div class="relative">
              <button
                @click="toggleNotifications"
                class="relative p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors">
                <svg class="size-6 text-gray-600 dark:text-gray-400"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
                  <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                </svg>
                <span
                  v-if="unreadCount > 0"
                  class="absolute top-1 right-1 size-5 bg-red-500 text-white text-xs rounded-full flex items-center justify-center">
                  {{ unreadCount }}
                </span>
              </button>

              <!-- Notifications Dropdown -->
              <div
                v-if="showNotifications"
                class="absolute top-full right-0 mt-2 w-80 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-50">
                <div class="p-4 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
                  <h3 class="font-semibold">Notifications</h3>
                  <button
                    @click="markAllRead"
                    class="text-sm text-brand-600 hover:text-brand-700">
                    Mark all read
                  </button>
                </div>
                <div class="max-h-96 overflow-y-auto">
                  <div
                    v-for="notification in notifications"
                    :key="notification.id"
                    class="px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors border-b border-gray-100 dark:border-gray-700"
                    :class="{ 'bg-brand-50 dark:bg-brand-900/10': notification.unread }">
                    <div class="flex items-start gap-3">
                      <div class="size-8 bg-gray-200 dark:bg-gray-600 rounded-full flex items-center justify-center mt-0.5">
                        <span class="text-xs">{{ notification.type === 'share' ? '🔗' : notification.type === 'team' ? '👥' : '⏰' }}</span>
                      </div>
                      <div class="flex-1">
                        <p class="text-sm">{{ notification.message }}</p>
                        <p class="text-xs text-gray-500 mt-1">{{ notification.time }}</p>
                      </div>
                      <div v-if="notification.unread" class="size-2 bg-brand-500 rounded-full mt-2"></div>
                    </div>
                  </div>
                </div>
                <div class="p-3 border-t border-gray-200 dark:border-gray-700">
                  <button class="w-full text-center text-sm text-brand-600 hover:text-brand-700">
                    View all notifications
                  </button>
                </div>
              </div>
            </div>

            <!-- User Avatar -->
            <button class="size-9 bg-brand-500 rounded-full text-white font-medium">
              JD
            </button>
          </div>
        </div>
      </div>
    </header>

    <!-- Navigation Bar -->
    <nav class="bg-white border-b border-gray-200 dark:bg-gray-800 dark:border-gray-700">
      <div class="container mx-auto max-w-7xl px-4">
        <div class="flex items-center gap-1 -mb-px">
          <a
            v-for="item in navItems"
            :key="item.id"
            href="#"
            class="px-4 py-3 border-b-2 border-transparent hover:border-gray-300 transition-all flex items-center gap-2 text-sm font-medium"
            :class="item.id === 'team-secrets' ? 'border-brand-500 text-brand-600' : 'text-gray-600 dark:text-gray-400'">
            <span>{{ item.label }}</span>
            <span
              v-if="item.count"
              class="px-2 py-0.5 text-xs rounded-full"
              :class="item.id === 'team-secrets' ? 'bg-brand-100 text-brand-700' : 'bg-gray-100 text-gray-600'">
              {{ item.count }}
            </span>
          </a>
        </div>
      </div>
    </nav>

    <!-- Main Content with Team Sidebar -->
    <div class="container mx-auto max-w-7xl px-4 py-6">
      <div class="flex gap-6">
        <!-- Main Content -->
        <div class="flex-1">
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
            <h1 class="text-2xl font-bold mb-4">Team Secrets Dashboard</h1>

            <!-- Tabs for Team View -->
            <div class="flex gap-4 mb-6 border-b border-gray-200 dark:border-gray-700">
              <button class="pb-3 border-b-2 border-brand-500 text-brand-600 font-medium">
                Active Secrets
              </button>
              <button class="pb-3 border-b-2 border-transparent text-gray-600 hover:text-gray-800">
                Shared with Me
              </button>
              <button class="pb-3 border-b-2 border-transparent text-gray-600 hover:text-gray-800">
                Archived
              </button>
              <button class="pb-3 border-b-2 border-transparent text-gray-600 hover:text-gray-800">
                Audit Log
              </button>
            </div>

            <!-- Secret List -->
            <div class="space-y-3">
              <div v-for="i in 5"
:key="i"
class="p-4 border border-gray-200 dark:border-gray-700 rounded-lg hover:shadow-md transition-shadow">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <div class="size-10 bg-gray-100 dark:bg-gray-700 rounded flex items-center justify-center">
                      🔐
                    </div>
                    <div>
                      <h3 class="font-medium">Production API Keys</h3>
                      <p class="text-sm text-gray-500">Shared with 3 team members • Expires in 2 days</p>
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="px-2 py-1 text-xs bg-green-100 text-green-700 rounded-full">Active</span>
                    <button class="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
                      <svg class="size-4"
fill="none"
stroke="currentColor"
viewBox="0 0 24 24">
                        <path stroke-linecap="round"
stroke-linejoin="round"
stroke-width="2"
d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
                      </svg>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Team Sidebar -->
        <aside class="w-80 space-y-4">
          <!-- Team Info Card -->
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
            <h3 class="font-semibold mb-3">Team Info</h3>
            <div class="space-y-3">
              <div class="flex justify-between text-sm">
                <span class="text-gray-500">Team Plan</span>
                <span class="font-medium">Business</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-500">Members</span>
                <span class="font-medium">12 / 20</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-500">Storage Used</span>
                <span class="font-medium">234 MB</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-500">API Calls</span>
                <span class="font-medium">8,421 / 10,000</span>
              </div>
              <button class="w-full mt-4 px-4 py-2 bg-brand-500 text-white rounded-lg hover:bg-brand-600 transition-colors text-sm font-medium">
                Upgrade Plan
              </button>
            </div>
          </div>

          <!-- Active Members -->
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-semibold">Active Members</h3>
              <button class="text-sm text-brand-600 hover:text-brand-700">
                Manage
              </button>
            </div>
            <div class="space-y-2">
              <div v-for="i in 4"
:key="i"
class="flex items-center gap-3">
                <div class="size-8 bg-gray-200 dark:bg-gray-600 rounded-full"></div>
                <div class="flex-1">
                  <div class="text-sm font-medium">Team Member {{ i }}</div>
                  <div class="text-xs text-gray-500">Active now</div>
                </div>
                <div class="size-2 bg-green-500 rounded-full"></div>
              </div>
            </div>
            <button class="w-full mt-3 text-sm text-brand-600 hover:text-brand-700">
              View all members
            </button>
          </div>

          <!-- Recent Activity -->
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
            <h3 class="font-semibold mb-3">Recent Activity</h3>
            <div class="space-y-3 text-sm">
              <div class="flex items-start gap-2">
                <div class="size-6 bg-green-100 text-green-600 rounded-full flex items-center justify-center text-xs mt-0.5">
                  ✓
                </div>
                <div>
                  <p>Sarah created "Database Credentials"</p>
                  <p class="text-xs text-gray-500">2 minutes ago</p>
                </div>
              </div>
              <div class="flex items-start gap-2">
                <div class="size-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center text-xs mt-0.5">
                  🔗
                </div>
                <div>
                  <p>Mike shared "API Documentation"</p>
                  <p class="text-xs text-gray-500">15 minutes ago</p>
                </div>
              </div>
              <div class="flex items-start gap-2">
                <div class="size-6 bg-red-100 text-red-600 rounded-full flex items-center justify-center text-xs mt-0.5">
                  🔥
                </div>
                <div>
                  <p>System burned expired secret</p>
                  <p class="text-xs text-gray-500">1 hour ago</p>
                </div>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Smooth transitions */
button {
  transition: all 0.2s ease;
}
</style>
