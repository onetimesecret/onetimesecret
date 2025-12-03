<!-- src/apps/colonel/views/ColonelSystem.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import QueueStatus from '@/apps/colonel/components/QueueStatus.vue';
  import { WindowService } from '@/services/window.service';
  import { computed } from 'vue';

  const windowProps = WindowService.getMultiple(['authentication']);

  // System sections with conditional visibility
  const systemSections = computed(() => {
    const sections = [
      {
        name: 'Configuration',
        description: 'View and manage system configuration settings',
        href: '/colonel/settings',
        icon: { collection: 'material-symbols', name: 'settings-outline' },
        color: 'bg-orange-500',
      },
      {
        name: 'Main Database (Redis)',
        description: 'Redis monitoring, metrics, and database statistics',
        href: '/colonel/database/maindb',
        icon: { collection: 'heroicons', name: 'circle-stack' },
        color: 'bg-green-500',
      },
    ];

    // Conditionally add Auth Database if authentication mode is full
    if (windowProps.authentication?.mode === 'full') {
      sections.push({
        name: 'Auth Database',
        description: 'SQLite/PostgreSQL authentication database monitoring',
        href: '/colonel/database/authdb',
        icon: { collection: 'heroicons', name: 'key' },
        color: 'bg-indigo-500',
      });
    }

    return sections;
  });
</script>

<template>
  <div>
    <!-- Header -->
    <div class="mb-6">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
        System
      </h1>
      <p class="mt-1 text-gray-600 dark:text-gray-400">
        System configuration, databases, and infrastructure monitoring
      </p>
    </div>

    <!-- System sections -->
    <div class="space-y-2">
      <a
        v-for="section in systemSections"
        :key="section.name"
        :href="section.href"
        class="dark:hover:bg-gray-750 group flex items-center justify-between rounded-lg bg-white p-4 shadow transition-all duration-200 hover:shadow-md dark:bg-gray-800">
        <div class="flex items-center space-x-3">
          <div
            class="flex size-10 items-center justify-center rounded-md text-white"
            :class="section.color">
            <OIcon
              :collection="section.icon.collection"
              :name="section.icon.name"
              class="size-5" />
          </div>
          <div>
            <h3
              class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
              {{ section.name }}
            </h3>
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {{ section.description }}
            </p>
          </div>
        </div>
        <OIcon
          name="arrow-right"
          collection="heroicons"
          class="size-4 text-gray-400 group-hover:text-brand-500 dark:group-hover:text-brand-400" />
      </a>
    </div>

    <!-- Queue Status Section -->
    <div class="mt-6">
      <QueueStatus />
    </div>
  </div>
</template>
