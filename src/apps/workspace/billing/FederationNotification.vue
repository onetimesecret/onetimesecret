<!-- src/apps/workspace/billing/FederationNotification.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { createApi } from '@/api';
import { ref, computed } from 'vue';

const { t } = useI18n();
const $api = createApi();

interface FederationNotificationData {
  show: boolean;
  source_region?: string;
}

const props = defineProps<{
  /** Organization external ID for the dismissal API call */
  orgExtid: string;
  /** Federation notification data from the billing API */
  notification: FederationNotificationData;
}>();

const emit = defineEmits<{
  /** Emitted after successful dismissal */
  dismissed: [];
}>();

const isDismissing = ref(false);
const isDismissed = ref(false);

const shouldShow = computed(() => props.notification.show && !isDismissed.value);

const handleDismiss = async () => {
  if (isDismissing.value) return;

  isDismissing.value = true;

  try {
    await $api.post(`/billing/api/org/${props.orgExtid}/dismiss-federation-notification`);
    isDismissed.value = true;
    emit('dismissed');
  } catch (err: unknown) {
    console.error('[FederationNotification] Failed to dismiss notification:', err);
    // Still hide the notification locally even if the API call fails
    // The user can always refresh to see it again if needed
    isDismissed.value = true;
  } finally {
    isDismissing.value = false;
  }
};
</script>

<template>
  <div
    v-if="shouldShow"
    class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20"
    role="status"
    aria-live="polite"
    data-testid="federation-notification">
    <div class="flex items-start justify-between gap-4">
      <div class="flex items-start gap-3">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          class="mt-0.5 size-5 text-blue-500 dark:text-blue-400"
          aria-hidden="true" />
        <div>
          <p class="font-medium text-blue-800 dark:text-blue-300">
            {{ t('web.billing.subscription_synced_title') }}
          </p>
          <p class="mt-1 text-sm text-blue-700 dark:text-blue-400">
            {{ t('web.billing.subscription_synced_description') }}
          </p>
        </div>
      </div>
      <button
        type="button"
        :disabled="isDismissing"
        class="-m-1 rounded p-1 text-blue-500 transition-colors hover:bg-blue-100 hover:text-blue-700 disabled:cursor-not-allowed disabled:opacity-50 dark:text-blue-400 dark:hover:bg-blue-800/50 dark:hover:text-blue-300"
        :aria-label="t('web.LABELS.dismiss')"
        @click="handleDismiss">
        <OIcon
          v-if="!isDismissing"
          collection="heroicons"
          name="x-mark"
          class="size-5"
          aria-hidden="true" />
        <OIcon
          v-else
          collection="heroicons"
          name="arrow-path"
          class="size-5 animate-spin"
          aria-hidden="true" />
      </button>
    </div>
  </div>
</template>
