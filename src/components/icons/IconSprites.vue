<script setup lang="ts">
  import { type PropType, computed } from 'vue';
  import type { IconSet } from './sprites';
  import { iconLibraries } from './sprites';

  const props = defineProps({
    icons: {
      type: Array as PropType<IconSet[]>,
      required: true,
    },
  });

  const getLibraryInfo = (prefix: string) => {
    return Object.values(iconLibraries).find((lib) => prefix.startsWith(lib.usagePrefix));
  };

  const formatIconName = (iconId: string): string => {
    return iconId.split('-').slice(-1)[0].replace(/-/g, ' ');
  };

  const groupedIcons = computed(() => {
    return props.icons.reduce((groups, icon) => {
      const group = groups[icon.name] || [];
      groups[icon.name] = [...group, icon];
      return groups;
    }, {} as Record<string, IconSet[]>);
  });
</script>

<template>
  <div class="space-y-8">
    <template
      v-for="(icons, name) in groupedIcons"
      :key="name">
      <div class="border-b pb-8 dark:border-gray-700">
        <div class="mb-4 flex items-baseline justify-between">
          <h2 class="text-xl font-medium dark:text-gray-200">{{ name }}</h2>
          <div
            v-if="getLibraryInfo(icons[0].prefix)"
            class="text-sm text-gray-600 dark:text-gray-400">
          </div>
        </div>

        <div class="grid grid-cols-2 gap-6 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
          <div
            v-for="icon in icons"
            :key="icon.id"
            class="flex flex-col items-center rounded border bg-white p-4 transition-shadow hover:shadow-md dark:border-gray-700 dark:bg-gray-800 dark:hover:shadow-gray-800">
            <div class="flex h-12 w-12 items-center justify-center">
              <svg class="h-8 w-8 text-gray-700 dark:text-gray-300">
                <use :href="`#${icon.id}`" />
              </svg>
            </div>
            <span class="mt-3 break-all text-center text-sm text-gray-600 dark:text-gray-400">
              {{ formatIconName(icon.id) }}
            </span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
