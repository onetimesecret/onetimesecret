<!-- src/apps/colonel/components/TestModeBanner.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useCsrfStore } from '@/shared/stores';
import { WindowService } from '@/services/window.service';
import { createApi } from '@/api';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const csrfStore = useCsrfStore();
const $api = createApi();

const isResetting = ref(false);

const testPlanName = computed(() => {
  try {
    // Backend sets 'entitlement_test_plan_name' (with underscore before 'name')
    return WindowService.get('entitlement_test_plan_name') || null;
  } catch {
    return null;
  }
});

const handleReset = async () => {
  isResetting.value = true;

  try {
    await $api.post(
      '/api/colonel/entitlement-test',
      { planid: null },
      {
        headers: {
          'Content-Type': 'application/json',
          'O-Shrimp': csrfStore.shrimp,
        },
      }
    );

    window.location.reload();
  } catch (err: unknown) {
    console.error('Failed to reset test mode:', err);
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
