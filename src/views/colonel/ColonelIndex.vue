<!-- src/views/colonel/ColonelIndex.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  // Main navigation tabs
  const navTabs = [
    { name: t('web.colonel.dashboard'), href: '/colonel', icon: 'home' },
    { name: t('web.colonel.activity'), href: '/colonel/activity', icon: 'chart-bar' },
    { name: t('web.colonel.accounts'), href: '/colonel/accounts', icon: 'users' },
    { name: t('web.colonel.domains'), href: '/colonel/domains', icon: 'globe-alt' },
    { name: t('web.colonel.settings'), href: '/colonel/settings', icon: 'cog-6-tooth' },
  ];

  // Quick stats - these would come from API calls in a real implementation
  const stats = computed(() => [
    {
      name: t('web.colonel.stats.totalSecrets'),
      value: '1,234',
      change: '+12%',
      changeType: 'increase' as const,
      icon: 'lock-closed',
    },
    {
      name: t('web.colonel.stats.activeUsers'),
      value: '89',
      change: '+5%',
      changeType: 'increase' as const,
      icon: 'users',
    },
    {
      name: t('web.colonel.stats.secretsToday'),
      value: '23',
      change: '-2%',
      changeType: 'decrease' as const,
      icon: 'calendar-days',
    },
    {
      name: t('web.colonel.stats.systemHealth'),
      value: t('web.colonel.stats.healthy'),
      change: null,
      changeType: 'neutral' as const,
      icon: 'heart',
    },
  ]);

  // Quick actions
  const quickActions = computed(() => [
    {
      name: t('web.colonel.actions.viewActivity'),
      description: t('web.colonel.actions.viewActivityDesc'),
      href: '/colonel/activity',
      icon: 'chart-bar',
      color: 'bg-blue-500',
    },
    {
      name: t('web.colonel.actions.manageAccounts'),
      description: t('web.colonel.actions.manageAccountsDesc'),
      href: '/colonel/accounts',
      icon: 'users',
      color: 'bg-green-500',
    },
    {
      name: t('web.colonel.actions.configureDomains'),
      description: t('web.colonel.actions.configureDomainsDesc'),
      href: '/colonel/domains',
      icon: 'globe-alt',
      color: 'bg-purple-500',
    },
    {
      name: t('web.colonel.actions.systemSettings'),
      description: t('web.colonel.actions.systemSettingsDesc'),
      href: '/colonel/settings',
      icon: 'cog-6-tooth',
      color: 'bg-orange-500',
    },
  ]);
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header with navigation -->
    <div class="bg-white shadow-sm dark:bg-gray-800">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <!-- Main navigation tabs -->
        <nav class="flex overflow-x-auto">
          <a
            v-for="tab in navTabs"
            :key="tab.href"
            :href="tab.href"
            class="mx-1 flex items-center border-b-2 border-transparent px-4 py-4 text-sm font-medium text-gray-700 transition-colors duration-150 first:ml-0 hover:border-brand-500 hover:text-brand-600 focus:border-brand-500 focus:outline-none dark:text-gray-200 dark:hover:border-brand-400 dark:hover:text-brand-400"
            :class="{
              'border-brand-500 text-brand-600 dark:text-brand-400': tab.href === '/colonel',
            }">
            <OIcon
              :name="tab.icon"
              collection="heroicons"
              class="mr-2 h-5 w-5" />
            {{ tab.name }}
          </a>
        </nav>
      </div>
    </div>

    <!-- Main content -->
    <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Welcome section -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          {{ t('web.colonel.welcome') }}
        </h1>
        <p class="mt-2 text-lg text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.welcomeDesc') }}
        </p>
      </div>

      <!-- Stats grid -->
      <div class="mb-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
        <div
          v-for="stat in stats"
          :key="stat.name"
          class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow dark:bg-gray-800 sm:p-6">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <OIcon
                :name="stat.icon"
                collection="heroicons"
                class="h-8 w-8 text-gray-400 dark:text-gray-500" />
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="truncate text-sm font-medium text-gray-500 dark:text-gray-400">
                  {{ stat.name }}
                </dt>
                <dd class="flex items-baseline">
                  <div class="text-2xl font-semibold text-gray-900 dark:text-white">
                    {{ stat.value }}
                  </div>
                  <div
                    v-if="stat.change"
                    class="ml-2 flex items-baseline text-sm font-semibold"
                    :class="{
                      'text-green-600 dark:text-green-400': stat.changeType === 'increase',
                      'text-red-600 dark:text-red-400': stat.changeType === 'decrease',
                    }">
                    {{ stat.change }}
                  </div>
                </dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <!-- Quick actions grid -->
      <div class="mb-8">
        <h2 class="mb-6 text-xl font-semibold text-gray-900 dark:text-white">
          {{ t('web.colonel.quickActions') }}
        </h2>
        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          <a
            v-for="action in quickActions"
            :key="action.name"
            :href="action.href"
            class="dark:hover:bg-gray-750 group relative overflow-hidden rounded-lg bg-white p-6 shadow transition-all duration-200 hover:shadow-lg dark:bg-gray-800">
            <div class="flex items-center">
              <div
                class="flex h-12 w-12 items-center justify-center rounded-lg text-white"
                :class="action.color">
                <OIcon
                  :name="action.icon"
                  collection="heroicons"
                  class="h-6 w-6" />
              </div>
              <div class="ml-4 flex-1">
                <h3
                  class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
                  {{ action.name }}
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ action.description }}
                </p>
              </div>
              <OIcon
                name="arrow-right"
                collection="heroicons"
                class="h-5 w-5 text-gray-400 group-hover:text-brand-500 dark:group-hover:text-brand-400" />
            </div>
          </a>
        </div>
      </div>

      <!-- Recent activity section placeholder -->
      <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
            {{ t('web.colonel.recentActivity') }}
          </h2>
          <a
            href="/colonel/activity"
            class="text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.colonel.viewAll') }}
          </a>
        </div>
        <div class="py-8 text-center text-gray-500 dark:text-gray-400">
          <OIcon
            name="chart-bar"
            collection="heroicons"
            class="mx-auto mb-4 h-12 w-12" />
          <p>{{ t('web.colonel.activityPlaceholder') }}</p>
        </div>
      </div>
    </main>
  </div>
</template>
