<script setup lang="ts">
  import { computed, watchEffect } from 'vue';
  import { type Metadata, MetadataState, metadataStateSchema } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';
  import { getDisplayStatus, type DisplayStatus, getStatusText } from '@/utils/status';
  import { useSecretExpiration } from '@/composables/useSecretExpiration';

  interface Props {
    record: Metadata;
  }

  const props = defineProps<Props>();
  const { t } = useI18n();

  const { expirationState } = useSecretExpiration(
    props.record.created,
    props.record.expiration_in_seconds ?? 0
  );

  const status = computed((): DisplayStatus => {
    const stateValue = props.record.secret_state || props.record.state;
    const state = metadataStateSchema.parse(stateValue) as MetadataState;

    // Map expiration states to display states
    if (expirationState.value === 'expired') {
      return 'expired';
    }
    if (expirationState.value === 'warning') {
      return 'expiring_soon';
    }

    return getDisplayStatus(state);
  });

  // Status styling maps with enhanced design
  const statusClasses: Record<DisplayStatus, string> = {
    new: 'bg-gradient-to-r from-green-50 to-green-100 text-green-800 dark:from-green-900/60 dark:to-green-800/40 dark:text-green-300 border border-green-200 dark:border-green-800/50',
    unread: 'bg-gradient-to-r from-slate-50 to-slate-100 text-slate-800 dark:from-slate-900/60 dark:to-slate-800/40 dark:text-slate-300 border border-slate-200 dark:border-slate-800/50',
    viewed: 'bg-gradient-to-r from-blue-50 to-blue-100 text-blue-800 dark:from-blue-900/60 dark:to-blue-800/40 dark:text-blue-300 border border-blue-200 dark:border-blue-800/50',
    burned: 'bg-gradient-to-r from-yellow-50 to-yellow-100 text-yellow-800 dark:from-yellow-900/60 dark:to-yellow-800/40 dark:text-yellow-300 border border-yellow-200 dark:border-yellow-800/50',
    received: 'bg-gradient-to-r from-red-50 to-red-100 text-red-800 dark:from-red-900/60 dark:to-red-800/40 dark:text-red-300 border border-red-200 dark:border-red-800/50',
    expiring_soon: 'bg-gradient-to-r from-orange-50 to-orange-100 text-orange-800 dark:from-orange-900/60 dark:to-orange-800/40 dark:text-orange-300 border border-orange-200 dark:border-orange-800/50',
    orphaned: 'bg-gradient-to-r from-purple-50 to-purple-100 text-purple-800 dark:from-purple-900/60 dark:to-purple-800/40 dark:text-purple-300 border border-purple-200 dark:border-purple-800/50',
    expired: 'bg-gradient-to-r from-purple-50 to-purple-100 text-purple-800 dark:from-purple-900/60 dark:to-purple-800/40 dark:text-purple-300 border border-purple-200 dark:border-purple-800/50',
  };

  const statusIcon: Record<DisplayStatus, string> = {
    new: 'check-circle-outline',
    unread: 'mark-email-unread-outline',
    viewed: 'mark-email-unread-outline',
    burned: 'local-fire-department-rounded',
    received: 'mark-email-read-outline',
    expiring_soon: 'timer-outline',
    orphaned: 'warning-outline',
    expired: 'timer-off-outline',
  };

  const displayStatus = computed(() => getStatusText(status.value, t));

  // Handle invalid states
  watchEffect(() => {
    if (!status.value) {
      console.error(
        `Invalid metadata state: ${props.record?.state} || ${props.record?.secret_state}`
      );
    }
  });
</script>

<template>
<span
  class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium shadow-sm transition-all duration-200"
  :class="[
    statusClasses[status],
    {
      'animate-pulse': status === 'expiring_soon',
      'transform hover:scale-105': status !== 'expired',
      'opacity-75': status === 'expired'
    }
  ]"
  :title="displayStatus.description"
  role="status"
>
  <OIcon
    collection="material-symbols"
    :name="statusIcon[status]"
    class="w-4 h-4 mr-1.5"
  />
  {{ displayStatus.text }}
</span>
</template>

<style scoped>
/* Ensure high contrast in dark mode with enhanced styling */
.animate-pulse {
  animation: statusPulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}

@keyframes statusPulse {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0.7;
  }
}
</style>
