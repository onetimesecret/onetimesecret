<!-- src/views/colonel/ColonelIndex.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import ColonelNavigation from '@/components/colonel/ColonelNavigation.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  // Quick stats - these would come from API calls in a real implementation
  const stats = computed(() => [
    {
      name: t('web.colonel.stats.totalSecrets'),
      value: '1,234',
      change: '+12%',
      changeType: 'increase' as const,
      icon: { collection: 'heroicons', name: 'lock-closed' },
    },
    {
      name: t('web.colonel.stats.activeUsers'),
      value: '89',
      change: '+5%',
      changeType: 'increase' as const,
      icon: { collection: 'heroicons', name: 'globe-alt' },
    },
    {
      name: t('web.colonel.stats.secretsToday'),
      value: '23',
      change: '-2%',
      changeType: 'decrease' as const,
      icon: { collection: 'heroicons', name: 'clock' },
    },
    {
      name: t('web.colonel.stats.systemHealth'),
      value: t('web.colonel.stats.healthy'),
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'heart' },
    },
  ]);

  // Quick actions
  const quickActions = computed(() => [
    {
      name: t('web.colonel.actions.viewActivity'),
      description: t('web.colonel.actions.viewActivityDesc'),
      href: '/colonel/activity',
      icon: { collection: 'ph', name: 'activity' },
      color: 'bg-blue-500',
    },
    {
      name: t('web.colonel.actions.manageAccounts'),
      description: t('web.colonel.actions.manageAccountsDesc'),
      href: '/colonel/users',
      icon: { collection: 'heroicons', name: 'users' },
      color: 'bg-green-500',
    },
    {
      name: t('web.colonel.actions.systemSettings'),
      description: t('web.colonel.actions.systemSettingsDesc'),
      href: '/colonel/settings',
      icon: { collection: 'material-symbols', name: 'settings-outline' },
      color: 'bg-orange-500',
    },
  ]);
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header with navigation -->
    <ColonelNavigation />

    <!-- Main content -->
    <main class="mx-auto max-w-3xl px-4 py-6 sm:px-6">
      <!-- Welcome section -->
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.colonel.welcome') }}
        </h1>
        <p class="mt-1 text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.welcomeDesc') }}
        </p>
      </div>

      <!-- Stats grid -->
      <div class="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div
          v-for="stat in stats"
          :key="stat.name"
          class="overflow-hidden rounded-lg bg-white px-3 py-3 shadow dark:bg-gray-800">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <OIcon
                :collection="stat.icon.collection"
                :name="stat.icon.name"
                class="h-6 w-6 text-gray-400 dark:text-gray-500" />
              <div>
                <dt class="text-xs font-medium text-gray-500 dark:text-gray-400">
                  {{ stat.name }}
                </dt>
                <dd class="text-lg font-semibold text-gray-900 dark:text-white">
                  {{ stat.value }}
                </dd>
              </div>
            </div>
            <div
              v-if="stat.change"
              class="text-xs font-semibold"
              :class="{
                'text-green-600 dark:text-green-400': stat.changeType === 'increase',
                'text-red-600 dark:text-red-400': stat.changeType === 'decrease',
              }">
              {{ stat.change }}
            </div>
          </div>
        </div>
      </div>

      <!-- Quick actions -->
      <div class="mb-6">
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.colonel.quickActions') }}
        </h2>
        <div class="space-y-2">
          <a
            v-for="action in quickActions"
            :key="action.name"
            :href="action.href"
            class="group flex items-center justify-between rounded-lg bg-white p-4 shadow transition-all duration-200 hover:shadow-md dark:bg-gray-800 dark:hover:bg-gray-750">
            <div class="flex items-center space-x-3">
              <div
                class="flex h-8 w-8 items-center justify-center rounded-md text-white"
                :class="action.color">
                <OIcon
                  :collection="action.icon.collection"
                  :name="action.icon.name"
                  class="h-4 w-4" />
              </div>
              <div>
                <h3
                  class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
                  {{ action.name }}
                </h3>
                <p class="text-xs text-gray-500 dark:text-gray-400">
                  {{ action.description }}
                </p>
              </div>
            </div>
            <OIcon
              name="arrow-right"
              collection="heroicons"
              class="h-4 w-4 text-gray-400 group-hover:text-brand-500 dark:group-hover:text-brand-400" />
          </a>
        </div>
      </div>

      <!-- Recent activity section placeholder -->
      <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('web.colonel.recentActivity') }}
          </h2>
          <a
            href="/colonel/activity"
            class="text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.colonel.viewAll') }}
          </a>
        </div>
        <div class="py-6 text-center text-gray-500 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="clipboard"
            class="mx-auto mb-3 h-8 w-8" />
          <p class="text-sm">{{ t('web.colonel.activityPlaceholder') }}</p>
        </div>
      </div>
    </main>
  </div>
</template>
