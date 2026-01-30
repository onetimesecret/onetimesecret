<!-- src/shared/components/ui/TestModeBanner.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useTestPlanMode } from '@/shared/composables/useTestPlanMode';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createApi } from '@/api';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const bootstrapStore = useBootstrapStore();
const $api = createApi();

// Test plan mode composable
const { testPlanName } = useTestPlanMode();

const isResetting = ref(false);

const handleReset = async () => {
  isResetting.value = true;

  try {
    await $api.post('/api/colonel/entitlement-test', { planid: null });

    // Refresh bootstrap state to clear test mode (no page reload needed)
    await bootstrapStore.refresh();
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
          {{ t('web.colonel.warningTestMode', { planName: testPlanName }) }}
        </p>
      </div>
      <button
        type="button"
        :disabled="isResetting"
        class="inline-flex items-center gap-2 rounded-md px-3 py-1 text-sm font-medium text-amber-900 transition-colors hover:bg-amber-200 disabled:cursor-not-allowed disabled:opacity-50 dark:text-amber-100 dark:hover:bg-amber-800/50"
        @click="handleReset">
        <span v-if="!isResetting">{{ t('web.colonel.clickToReset') }}</span>
        <span v-else>{{ t('web.COMMON.processing') }}</span>
      </button>
    </div>
  </div>
</template>
