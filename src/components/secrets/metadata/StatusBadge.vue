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

  // Status styling maps
  const statusClasses: Record<DisplayStatus, string> = {
    new: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300',
    unread: 'bg-slate-100 text-slate-800 dark:bg-slate-900 dark:text-slate-300',
    viewed: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300',
    burned: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300',
    received: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300',
    expiring_soon: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-300',
    orphaned: 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-300',
    expired: 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-300',
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
  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium transition-all duration-200"
  :class="[
    statusClasses[status],
    {
      'animate-pulse': status === 'expiring_soon',
      'hover:scale-105': status !== 'expired',
      'opacity-75': status === 'expired'
    }
  ]"
  :title="displayStatus.description"
  role="status"
>
  <OIcon
    collection="material-symbols"
    :name="statusIcon[status]"
    class="w-4 h-4 mr-1"
  />
  {{ displayStatus.text }}
</span>
</template>

<style scoped>
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
