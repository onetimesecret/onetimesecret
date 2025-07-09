<!-- src/views/colonel/ColonelUsers.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { isLoading } = storeToRefs(store);
  const { fetch } = store;

  onMounted(fetch);
</script>

<template>
  <div class="">
    <div
      v-if="isLoading"
      class="p-6 text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div
      v-else>
      <!-- Page header -->
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.colonel.users') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.usersDescription') }}
        </p>
      </div>
    </div>
  </div>
</template>
