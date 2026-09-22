<!-- src/shared/components/ui/PreviewModeBanner.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { usePreviewPlanMode } from '@/shared/composables/usePreviewPlanMode';
import { useAuthStore } from '@/shared/stores/authStore';
import { createApi } from '@/api';
import { storeToRefs } from 'pinia';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const authStore = useAuthStore();
const $api = createApi();

// The reset POSTs the same protected endpoint PlanPreviewModal does, so it
// follows the same gate (ADR-046#authority-action-gating): no mutation while
// authority is uncertain or the session is stale.
const { protectedActionsAvailable } = storeToRefs(authStore);

// Test plan mode composable
const { previewPlanName } = usePreviewPlanMode();

const isResetting = ref(false);

const handleReset = async () => {
  if (!protectedActionsAvailable.value) return;
  isResetting.value = true;

  try {
    await $api.post('/api/colonel/entitlement-preview', { planid: null });

    // Refresh bootstrap state to clear test mode (no page reload needed)
    await authStore.refresh({ kind: 'ordinary', reason: 'plan-preview' });
  } catch (err: unknown) {
    console.error('Failed to reset test mode:', err);
  } finally {
    isResetting.value = false;
  }
};
</script>

<template>
  <div
    class="border-b border-amber-300 bg-amber-100 px-4 py-2 dark:border-amber-800 dark:bg-amber-900/30"
    role="banner"
    aria-live="polite">
    <div class="container mx-auto flex items-center justify-between">
      <div class="flex items-center gap-3">
        <OIcon
          collection="heroicons"
          name="beaker"
          class="size-5 text-amber-700 dark:text-amber-400"
          aria-hidden="true" />
        <p class="text-sm font-medium text-amber-900 dark:text-amber-100">
          {{ t('web.colonel.warningTestMode', { planName: previewPlanName }) }}
        </p>
      </div>
      <button
        type="button"
        :disabled="isResetting || !protectedActionsAvailable"
        class="inline-flex items-center gap-2 rounded-md px-3 py-1 text-sm font-medium text-amber-900 transition-colors hover:bg-amber-200 disabled:cursor-not-allowed disabled:opacity-50 dark:text-amber-100 dark:hover:bg-amber-800/50"
        @click="handleReset">
        <span v-if="!isResetting">{{ t('web.colonel.clickToReset') }}</span>
        <span v-else>{{ t('web.COMMON.processing') }}</span>
      </button>
    </div>
  </div>
</template>
