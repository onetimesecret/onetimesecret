<!-- src/apps/workspace/components/billing/UpgradePromptLegacy.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

const { t } = useI18n();

const props = withDefaults(
  defineProps<{
    entitlement: string;
    upgradePlan: string;
    message?: string;
    compact?: boolean;
  }>(),
  {
    message: '',
    compact: false,
  }
);

// Hide upgrade prompts when billing is disabled (self-hosted mode)
const bootstrapStore = useBootstrapStore();
const { billing_enabled } = storeToRefs(bootstrapStore);
const billingEnabled = computed(() => billing_enabled.value || false);

const displayMessage = computed(() => {
  if (props.message) return props.message;

  // Default messages based on entitlement
  const entitlementMessages: Record<string, string> = {
    manage_teams: t('web.billing.upgrade.needTeams'),
    custom_domains: t('web.billing.upgrade.needCustomDomains'),
    api_access: t('web.billing.upgrade.needApiAccess'),
  };

  return entitlementMessages[props.entitlement] || t('web.billing.upgrade.required');
});

const upgradeUrl = computed(() => `/billing/plans?upgrade_to=${props.upgradePlan}`);
</script>

<template>
  <!-- Hidden when billing is disabled (self-hosted mode) -->
  <div
    v-if="billingEnabled"
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

      <div class="min-w-0 flex-1">
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
