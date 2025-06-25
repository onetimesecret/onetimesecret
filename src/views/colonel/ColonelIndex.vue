<!-- src/views/colonel/ColonelIndex.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { stats, isLoading } = storeToRefs(store);
  const { fetchStats } = store;

  onMounted(fetchStats);

  // Quick stats using real data from the store
  const statsData = computed(() => [
    {
      name: t('web.colonel.stats.secretsCreated'),
      value: stats.value?.counts?.secrets_created?.toLocaleString() || '0',
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'plus-circle' },
    },
    {
      name: t('web.colonel.stats.secretsShared'),
      value: stats.value?.counts?.secrets_shared?.toLocaleString() || '0',
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'share' },
    },
    {
      name: t('web.colonel.stats.activeUsers'),
      value: stats.value?.counts?.session_count?.toString() || '0',
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'users' },
    },
    {
      name: t('web.colonel.stats.emailsSent'),
      value: stats.value?.counts?.emails_sent?.toLocaleString() || '0',
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'envelope' },
    },
    {
      name: t('web.colonel.stats.totalSecrets'),
      value: stats.value?.counts?.secret_count?.toLocaleString() || '0',
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'lock-closed' },
    },
    {
      name: t('web.colonel.stats.totalCustomers'),
      value: stats.value?.counts?.customer_count?.toLocaleString() || '0',
      change: null,
      changeType: 'neutral' as const,
      icon: { collection: 'heroicons', name: 'user-group' },
    },
  ]);

  // Quick actions
  const quickActions = computed(() => [
    {
      name: t('web.colonel.recentActivity'),
      description: t('web.colonel.actions.viewActivityDesc'),
      href: '/colonel/info',
      icon: { collection: 'ph', name: 'activity' },
      color: 'bg-blue-500',
    },
    {
      name: t('web.colonel.actions.mutableConfig'),
      description: t('web.colonel.actions.mutableConfigDesc'),
      href: '/colonel/settings',
      icon: { collection: 'material-symbols', name: 'settings-outline' },
      color: 'bg-orange-500',
    },
  ]);
</script>

<template>
  <div>
    <!-- Welcome section -->
    <div class="mb-6">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
        {{ t('web.colonel.welcome') }}
      </h1>
      <p class="mt-1 text-gray-600 dark:text-gray-400">
        {{ t('web.colonel.welcomeDesc') }}
      </p>
    </div>

    <!-- Loading state -->
    <div
      v-if="isLoading"
      class="mb-6 p-4 text-center text-gray-600 dark:text-gray-400">
      {{ t('web.LABELS.loading') }}
    </div>

    <!-- System Status Banner -->
    <div
      v-if="stats"
      class="mb-6 rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-700 dark:bg-green-900/20">
      <div class="flex items-center">
        <OIcon
          collection="heroicons"
          name="check-circle"
          class="h-5 w-5 text-green-500 dark:text-green-400" />
        <p class="ml-2 text-sm text-green-800 dark:text-green-200">
          {{ t('web.colonel.stats.systemHealth') }}:
          <span class="font-semibold">{{ t('web.colonel.stats.healthy') }}</span>
          • {{ stats.counts.session_count }} active sessions
        </p>
      </div>
    </div>

    <!-- Stats grid -->
    <div
      v-if="!isLoading"
      class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="stat in statsData"
        :key="stat.name"
        class="overflow-hidden rounded-lg bg-white px-4 py-5 shadow transition-shadow hover:shadow-md dark:bg-gray-800">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div
              class="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-900/20">
              <OIcon
                :collection="stat.icon.collection"
                :name="stat.icon.name"
                class="h-5 w-5 text-brand-600 dark:text-brand-400" />
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ stat.name }}
              </dt>
              <dd class="text-2xl font-bold text-gray-900 dark:text-white">
                {{ stat.value }}
              </dd>
            </div>
          </div>
          <div
            v-if="stat.change"
            class="text-xs font-semibold text-gray-500 dark:text-gray-400">
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
          class="dark:hover:bg-gray-750 group flex items-center justify-between rounded-lg bg-white p-4 shadow transition-all duration-200 hover:shadow-md dark:bg-gray-800">
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
  </div>
</template>
