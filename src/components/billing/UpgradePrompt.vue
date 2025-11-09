<!-- src/components/billing/UpgradePrompt.vue -->

<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import OIcon from '@/components/icons/OIcon.vue';

const { t } = useI18n();

const props = withDefaults(
  defineProps<{
    capability: string;
    upgradePlan: string;
    message?: string;
    compact?: boolean;
  }>(),
  {
    message: '',
    compact: false,
  }
);

const displayMessage = computed(() => {
  if (props.message) return props.message;

  // Default messages based on capability
  const capabilityMessages: Record<string, string> = {
    create_teams: t('web.billing.upgrade.needTeams'),
    custom_domains: t('web.billing.upgrade.needCustomDomains'),
    api_access: t('web.billing.upgrade.needApiAccess'),
  };

  return capabilityMessages[props.capability] || t('web.billing.upgrade.required');
});

const upgradeUrl = computed(() => `/account/billing/plans?upgrade_to=${props.upgradePlan}`);
</script>

<template>
  <div
    :class="[
      'rounded-lg border bg-gradient-to-br',
      compact
        ? 'border-amber-200 from-amber-50 to-amber-100/50 p-4 dark:border-amber-800 dark:from-amber-900/20 dark:to-amber-900/10'
        : 'border-amber-200 from-amber-50 to-amber-100/50 p-6 dark:border-amber-800 dark:from-amber-900/20 dark:to-amber-900/10',
    ]">
    <div :class="['flex gap-4', compact ? 'items-center' : 'items-start']">
      <div class="shrink-0">
        <OIcon
          collection="tabler"
          name="square-letter-s"
          :class="[
            'text-amber-600 dark:text-amber-400',
            compact ? 'size-5' : 'size-6',
          ]"
          aria-hidden="true" />
      </div>

      <div class="flex-1 min-w-0">
        <h4
          v-if="!compact"
          class="text-base font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.upgrade.required') }}
        </h4>
        <p
          :class="[
            'text-gray-700 dark:text-gray-300',
            compact ? 'text-sm' : 'mt-1 text-sm',
          ]">
          {{ displayMessage }}
        </p>
      </div>

      <div class="shrink-0">
        <router-link
          :to="upgradeUrl"
          :class="[
            'inline-flex items-center gap-2 rounded-md bg-amber-600 font-semibold text-white shadow-sm hover:bg-amber-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 dark:bg-amber-500 dark:hover:bg-amber-400',
            compact ? 'px-3 py-1.5 text-xs' : 'px-3 py-2 text-sm',
          ]">
          <OIcon
            collection="heroicons"
            name="arrow-up-circle"
            :class="compact ? 'size-4' : 'size-5'"
            aria-hidden="true" />
          {{ t('web.billing.upgrade.viewPlans') }}
        </router-link>
      </div>
    </div>
  </div>
</template>
