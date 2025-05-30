<!-- src/views/colonel/ColonelUsers.vue -->

<script setup lang="ts">
  import ColonelNavigation from '@/components/colonel/ColonelNavigation.vue';
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { onMounted } from 'vue';
  import { storeToRefs } from 'pinia';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { isLoading } = storeToRefs(store);
  const { fetch } = store;

  onMounted(fetch);
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header with navigation -->
    <ColonelNavigation />

    <!-- Main content -->
    <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
        <div
          v-if="isLoading"
          class="p-6 text-center">
          {{ t('web.LABELS.loading') }}
        </div>

        <div
          v-else
          class="p-6">
          <!-- Page header -->
          <div class="mb-8">
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
              {{ t('web.colonel.users') }}
            </h1>
            <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.usersDescription') }}
            </p>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>
