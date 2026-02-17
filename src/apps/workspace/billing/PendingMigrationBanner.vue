<!-- src/apps/workspace/billing/PendingMigrationBanner.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { computed } from 'vue';

const { t } = useI18n();

const props = defineProps<{
  targetPlanName: string;
  targetCurrency: string;
  effectiveDate: number;
  isCompletingMigration?: boolean;
}>();

const emit = defineEmits<{
  (e: 'complete-migration'): void;
}>();

const formattedDate = computed(() =>
  new Date(props.effectiveDate * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
);

const currencyUpper = computed(() => props.targetCurrency.toUpperCase());
</script>

<template>
  <div
    class="rounded-lg border-2 border-blue-300 bg-blue-50 p-5 dark:border-blue-600 dark:bg-blue-900/30"
    role="status">
    <div class="flex items-start gap-4">
      <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-blue-100 dark:bg-blue-800">
        <OIcon
          collection="heroicons"
          name="clock"
          class="size-6 text-blue-600 dark:text-blue-300"
          aria-hidden="true" />
      </div>
      <div class="flex-1">
        <h3 class="text-base font-semibold text-blue-800 dark:text-blue-200">
          {{ t('web.billing.currency_migration.pending_title') }}
        </h3>
        <p class="mt-1 text-sm text-blue-700 dark:text-blue-300">
          {{ t('web.billing.currency_migration.pending_description', {
            date: formattedDate,
            plan: targetPlanName,
            currency: currencyUpper,
          }) }}
        </p>
        <div class="mt-3">
          <button
            type="button"
            :disabled="isCompletingMigration"
            class="inline-flex items-center rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-blue-500 dark:hover:bg-blue-400"
            @click="emit('complete-migration')">
            <OIcon
              v-if="isCompletingMigration"
              collection="heroicons"
              name="arrow-path"
              class="mr-2 size-4 animate-spin"
              aria-hidden="true" />
            {{ isCompletingMigration
              ? t('web.COMMON.processing')
              : t('web.billing.currency_migration.complete_migration')
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
