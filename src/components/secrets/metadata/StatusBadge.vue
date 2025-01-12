<script setup lang="ts">
  import { computed } from 'vue';
  import { type Metadata } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';
  import { getDisplayStatus, type DisplayStatus, getStatusText } from '@/utils/status';

  interface Props {
    record: Metadata;
    expiresIn?: number; // Time in seconds until expiration
  }

  const props = defineProps<Props>();
  const { t } = useI18n();

  const status = computed(() => getDisplayStatus(props.record, props.expiresIn));

  const statusClasses: Record<DisplayStatus, string> = {
    active: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300',
    received: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300',
    burned: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300',
    destroyed: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300',
    'expiring-soon':
      'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-300',
    processing: 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-300',
    secured: 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-300',
  };

  const statusIcon: Record<DisplayStatus, string> = {
    active: 'check-circle-outline',
    received: 'mark-email-read-outline',
    burned: 'local-fire-department',
    destroyed: 'block',
    'expiring-soon': 'timer-outline',
    processing: 'refresh',
    secured: 'refresh',
  };

  const displayStatus = computed(() => getStatusText(status.value, t));
</script>

<template>
  <span
    class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium transition-all duration-200 hover:scale-105"
    :class="[statusClasses[status], { 'animate-pulse': status === 'expiring-soon' }]"
    :title="displayStatus.description"
    role="status">
    <OIcon
      collection="material-symbols"
      :name="statusIcon[status]"
      class="w-4 h-4 mr-1"
      :class="{ 'animate-spin-slow': status === 'secured' }" />
    {{ displayStatus.text }}
  </span>
</template>

<style scoped>
  .animate-spin-slow {
    animation: spin 2s linear infinite;
  }

  @keyframes spin {
    from {
      transform: rotate(0deg);
    }
    to {
      transform: rotate(360deg);
    }
  }

  /* Ensure high contrast in dark mode */
  :deep(.dark) .text-green-800 {
    color: rgb(22, 101, 52);
  }
  :deep(.dark) .text-blue-800 {
    color: rgb(30, 64, 175);
  }
  :deep(.dark) .text-yellow-800 {
    color: rgb(133, 77, 14);
  }
  :deep(.dark) .text-red-800 {
    color: rgb(153, 27, 27);
  }
  :deep(.dark) .text-orange-800 {
    color: rgb(154, 52, 18);
  }
  :deep(.dark) .text-purple-800 {
    color: rgb(107, 33, 168);
  }
</style>
