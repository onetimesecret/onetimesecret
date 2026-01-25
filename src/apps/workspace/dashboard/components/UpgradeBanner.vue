<!-- src/apps/workspace/dashboard/components/UpgradeBanner.vue -->

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { storeToRefs } from 'pinia';

const { t } = useI18n();
const organizationStore = useOrganizationStore();

const STORAGE_KEY = 'ots_upgrade_banner_dismissed';

// Initialize from localStorage for persistence across sessions
const dismissed = ref(localStorage.getItem(STORAGE_KEY) === 'true');

// Get the first organization (default org for billing context)
const currentOrg = computed(() => organizationStore.organizations[0] ?? null);

const { planId, isStandaloneMode } = useEntitlements(currentOrg);

// Check if billing is enabled via bootstrapStore
const bootstrapStore = useBootstrapStore();
const { billing_enabled } = storeToRefs(bootstrapStore);
const billingEnabled = computed(() => billing_enabled.value === true);

// Determine if user is on free plan (null, undefined, or 'free')
const isFreePlan = computed(() => {
  if (isStandaloneMode.value) return false;
  const plan = planId.value;
  return !plan || plan === 'free';
});

// Show banner only when billing is enabled, user is on free plan, and not dismissed
const showBanner = computed(() => billingEnabled.value && isFreePlan.value && !dismissed.value);

const handleDismiss = () => {
  dismissed.value = true;
  localStorage.setItem(STORAGE_KEY, 'true');
};
</script>

<template>
  <div
    v-if="showBanner"
    role="region"
    aria-label="Upgrade offer"
    class="mb-6 rounded-lg border border-brand-200 bg-gradient-to-br from-brand-50 to-brand-100/50 p-4 dark:border-brand-800 dark:from-brand-900/20 dark:to-brand-900/10">
    <div class="flex items-start gap-3">
      <!-- Icon -->
      <div class="shrink-0">
        <OIcon
          collection="heroicons"
          name="sparkles"
          class="size-6 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
      </div>

      <!-- Content -->
      <div class="min-w-0 flex-1">
        <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.upgrade_to_identity_plus') }}
        </h3>
        <p class="mt-1 text-sm text-gray-700 dark:text-gray-300">
          {{ t('web.billing.elevate_your_secure_sharing_with_custom_domains_') }}
        </p>
        <div class="mt-3 flex flex-wrap gap-2">
          <router-link
            v-if="currentOrg?.extid"
            :to="`/billing/${currentOrg.extid}/plans`"
            class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-1.5 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
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
          @click="handleDismiss"
          class="rounded-md text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:text-gray-500 dark:hover:text-gray-400"
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
