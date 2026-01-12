<!-- src/apps/workspace/components/billing/EntitlementUpgradePrompt.vue -->

<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { ApplicationError } from '@/schemas/errors';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';

const { t } = useI18n();

interface Props {
  error: ApplicationError | null;
  resourceType?: string;
  show?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  resourceType: '',
  show: true,
});

const emit = defineEmits<{
  close: [];
  'update:show': [value: boolean];
}>();

// Hide upgrade prompts when billing is disabled (self-hosted mode)
const bootstrapStore = useBootstrapStore();
const { billing_enabled } = storeToRefs(bootstrapStore);
const billingEnabled = computed(() => billing_enabled.value || false);

const displayMessage = computed(() => {
  if (!props.error) return '';
  return props.error.message || t('web.billing.upgrade.required');
});

const upgradeUrl = computed(() => '/billing/plans');

const handleClose = () => {
  emit('close');
  emit('update:show', false);
};
</script>

<template>
  <!-- Only show when billing is enabled and component is visible -->
  <div
    v-if="billingEnabled && show && error"
    role="alert"
    aria-live="polite"
    class="rounded-lg border border-amber-200 bg-gradient-to-br from-amber-50 to-amber-100/50 p-4 dark:border-amber-800 dark:from-amber-900/20 dark:to-amber-900/10">
    <div class="flex items-start gap-3">
      <!-- Icon -->
      <div class="shrink-0">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="size-5 text-amber-600 dark:text-amber-400"
          aria-hidden="true" />
      </div>

      <!-- Content -->
      <div class="min-w-0 flex-1">
        <h4 class="text-sm font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.upgrade.required') }}
        </h4>
        <p class="mt-1 text-sm text-gray-700 dark:text-gray-300">
          {{ displayMessage }}
        </p>
        <div class="mt-3">
          <router-link
            :to="upgradeUrl"
            class="inline-flex items-center gap-2 rounded-md bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-amber-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 dark:bg-amber-500 dark:hover:bg-amber-400">
            <OIcon
              collection="heroicons"
              name="arrow-up-circle"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.billing.upgrade.viewPlans') }}
          </router-link>
        </div>
      </div>

      <!-- Close button -->
      <div class="shrink-0">
        <button
          type="button"
          @click="handleClose"
          class="rounded-md text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2 dark:text-gray-500 dark:hover:text-gray-400"
          :aria-label="t('web.LABELS.dismiss')">
          <OIcon
            collection="heroicons"
            name="x-mark"
            class="size-5"
            aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>
</template>
