<!-- src/apps/colonel/views/ColonelIndex.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { WindowService } from '@/services/window.service';
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';

  const { t } = useI18n();

  const windowProps = WindowService.getMultiple(['domains_enabled', 'authentication']);

  const store = useColonelInfoStore();
  const { stats, isLoading } = storeToRefs(store);
  const { fetchStats } = store;

  onMounted(fetchStats);

  // Helper function to create stat item
  const createStatItem = (nameKey: string, value: string, iconName: string) => ({
    name: t(nameKey),
    value,
    change: null,
    changeType: 'neutral' as const,
    icon: { collection: 'heroicons', name: iconName },
  });

  const getEmailsSentStat = () => createStatItem(
    'web.colonel.stats.emailsSent',
    stats.value?.counts?.emails_sent?.toLocaleString() || '0',
    'envelope'
  );

  const getTotalSecretsStat = () => createStatItem(
    'web.colonel.stats.totalSecrets',
    stats.value?.counts?.secret_count?.toLocaleString() || '0',
    'lock-closed'
  );

  const getTotalCustomersStat = () => createStatItem(
    'web.colonel.stats.totalCustomers',
    stats.value?.counts?.customer_count?.toLocaleString() || '0',
    'users'
  );

  // Helper function to get stats data
  const getStatsData = () => [
    getTotalCustomersStat(),
    getTotalSecretsStat(),
    getEmailsSentStat(),
  ];

  // Quick stats using real data from the store
  const statsData = computed(getStatsData);

  // Quick actions with conditional visibility
  const quickActions = computed(() => {
    const actions = [
      {
        name: t('web.colonel.users'),
        description: t('web.colonel.usersDescription'),
        href: '/colonel/users',
        icon: { collection: 'heroicons', name: 'users' },
        color: 'bg-blue-500',
      },
      {
        name: t('web.colonel.secrets.title'),
        description: t('web.colonel.secrets.description'),
        href: '/colonel/secrets',
        icon: { collection: 'heroicons', name: 'lock-closed' },
        color: 'bg-purple-500',
      },
      {
        name: t('web.colonel.bannedIps.title'),
        description: t('web.colonel.bannedIps.description'),
        href: '/colonel/banned-ips',
        icon: { collection: 'heroicons', name: 'shield-exclamation' },
        color: 'bg-red-500',
      },
      {
        name: t('web.colonel.usageExport.title'),
        description: t('web.colonel.usageExport.description'),
        href: '/colonel/usage',
        icon: { collection: 'heroicons', name: 'document-chart-bar' },
        color: 'bg-cyan-500',
      },
      {
        name: t('web.colonel.systemSettings.title'),
        description: t('web.colonel.systemSettings.description'),
        href: '/colonel/system',
        icon: { collection: 'material-symbols', name: 'settings-outline' },
        color: 'bg-orange-500',
      },
    ];

    // Conditionally add Custom Domains if domains feature is enabled
    if (windowProps.domains_enabled) {
      actions.splice(2, 0, {
        name: t('web.colonel.customDomains.title'),
        description: t('web.colonel.customDomains.description'),
        href: '/colonel/domains',
        icon: { collection: 'heroicons', name: 'globe-alt' },
        color: 'bg-pink-500',
      });
    }

    // Add Organizations billing admin
    actions.splice(actions.length - 1, 0, {
      name: t('web.colonel.organizations.title'),
      description: t('web.colonel.organizations.description'),
      href: '/colonel/organizations',
      icon: { collection: 'heroicons', name: 'building-office-2' },
      color: 'bg-indigo-500',
    });

    return actions;
  });
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
          class="size-5 text-green-500 dark:text-green-400" />
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
              class="flex size-10 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-900/20">
              <OIcon
                :collection="stat.icon.collection"
                :name="stat.icon.name"
                class="size-5 text-brand-600 dark:text-brand-400" />
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
              class="flex size-8 items-center justify-center rounded-md text-white"
              :class="action.color">
              <OIcon
                :collection="action.icon.collection"
                :name="action.icon.name"
                class="size-4" />
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
            class="size-4 text-gray-400 group-hover:text-brand-500 dark:group-hover:text-brand-400" />
        </a>
      </div>
    </div>
  </div>
</template>
