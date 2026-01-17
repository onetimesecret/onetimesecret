<!-- src/apps/workspace/account/settings/OrganizationsSettings.vue -->

<!--
  Organizations list page - workspace feature for managing organizations.
  Uses WorkspaceLayout via route meta (not BillingLayout).
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import CreateOrganizationModal from '@/apps/workspace/components/organizations/CreateOrganizationModal.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';
import { getPlanDisplayName } from '@/types/billing';
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';

const { t } = useI18n();
const router = useRouter();
const organizationStore = useOrganizationStore();
const bootstrapStore = useBootstrapStore();

const isLoading = ref(false);
const showCreateModal = ref(false);

/**
 * Check if billing is enabled
 */
const billingEnabled = computed(() => bootstrapStore.billing_enabled);

/**
 * Check if an organization has a paid plan
 * Paid = planid exists and doesn't start with "free"
 */
const hasPaidPlan = (org: Organization): boolean => {
  if (!org.planid) return false;
  return !org.planid.toLowerCase().startsWith('free');
};

/**
 * Get display-friendly plan name for an organization
 */
const getOrgPlanName = (org: Organization): string => {
  if (!org.planid) return t('web.billing.plans.free_plan');
  return getPlanDisplayName(org.planid);
};

// Use the first organization to check entitlements for single-org users
const primaryOrg = computed(() => organizationStore.organizations[0] || null);
const primaryOrgRef = computed(() => primaryOrg.value);
const { can, ENTITLEMENTS } = useEntitlements(primaryOrgRef);

// Filter out default orgs for individual plan users (future plan-gating logic)
const visibleOrganizations = computed(() =>
  // For now, show all orgs. In future, filter by:
  // - User's plan (hide default org for individual plans)
  // - User's role (show only orgs where user is owner/admin)
   organizationStore.organizations
);

const hasOrganizations = computed(() => visibleOrganizations.value.length > 0);

/**
 * Determine if user can create multiple organizations based on entitlements.
 * Uses entitlement-based framework instead of hardcoded plan checks.
 */
const canCreateMultipleOrgs = computed(() =>
  // Users with team management entitlement can manage multiple organizations
  can(ENTITLEMENTS.MANAGE_TEAMS)
);

/**
 * Determine if user is on a single-user account (no team entitlements)
 */
const isSingleUserAccount = computed(() => !can(ENTITLEMENTS.MANAGE_TEAMS));

onMounted(async () => {
  isLoading.value = true;
  try {
    // Fetch organizations - each org includes domain_count from backend
    await organizationStore.fetchOrganizations();
  } catch (error) {
    console.error('[OrganizationsSettings] Error fetching organizations:', error);
  } finally {
    isLoading.value = false;
  }
});

const handleCreateOrganization = () => {
  showCreateModal.value = true;
};

const handleOrganizationCreated = (orgExtid: string) => {
  showCreateModal.value = false;
  // Navigate to the new organization's settings (using extid for URL)
  router.push(`/org/${orgExtid}`);
};

const handleManageOrganization = (org: Organization) => {
  // IMPORTANT: Always use extid (not id) for URL paths
  router.push(`/org/${org.extid}`);
};
</script>

<template>
  <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
    <!-- Page Header -->
    <div class="mb-8">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
        {{ t('web.organizations.manage_organizations') }}
      </h1>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.page_description') }}
      </p>
    </div>

    <div class="space-y-8">
      <!-- Organizations Section -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <OIcon
                collection="ph"
                name="building-office-bold"
                class="size-5 text-gray-500 dark:text-gray-400"
                aria-hidden="true" />
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.organizations.title') }}
              </h2>
            </div>
            <!--
              Organization CTA Logic:
              - Show "+ Create Organization" button ONLY when user has existing organizations
              - Show "+ Create First Organization" button ONLY in empty state (no organizations)
              - This prevents both CTAs from appearing simultaneously and provides contextual action based on user state
            -->
            <button
              v-if="hasOrganizations"
              @click="handleCreateOrganization"
              class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
              <OIcon
                collection="heroicons"
                name="plus"
                class="size-4"
                aria-hidden="true" />
              {{ t('web.organizations.create_organization') }}
            </button>
          </div>
        </div>

        <div class="p-6">
          <!-- Loading State -->
          <div v-if="isLoading" class="flex items-center justify-center py-12">
            <div class="text-center">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                class="mx-auto size-8 animate-spin text-gray-400"
                aria-hidden="true" />
              <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.COMMON.loading') }}
              </p>
            </div>
          </div>

          <!-- Organizations List -->
          <div v-else-if="hasOrganizations" class="space-y-4">
            <div
              v-for="org in visibleOrganizations"
              :key="org.id"
              class="rounded-lg border border-gray-200 p-4 transition-colors hover:border-brand-300 dark:border-gray-700 dark:hover:border-brand-600">
              <!-- Header row: Name + badges -->
              <div class="flex items-start justify-between">
                <div class="min-w-0 flex-1">
                  <button
                    type="button"
                    @click="handleManageOrganization(org)"
                    class="group flex items-center gap-2 text-left">
                    <h3 class="text-base font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
                      {{ org.display_name }}
                    </h3>
                    <OIcon
                      collection="heroicons"
                      name="chevron-right"
                      class="size-4 text-gray-400 transition-transform group-hover:translate-x-0.5 group-hover:text-brand-500"
                      aria-hidden="true" />
                  </button>
                  <p v-if="org.description" class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    {{ org.description }}
                  </p>
                </div>
                <div class="ml-4 flex shrink-0 items-center gap-2">
                  <!-- Pro badge for paid plans -->
                  <span
                    v-if="hasPaidPlan(org)"
                    class="inline-flex items-center rounded bg-brand-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-brand-700 dark:bg-brand-900/50 dark:text-brand-300">
                    {{ t('web.organizations.paid_badge') }}
                  </span>
                  <!-- Default badge -->
                  <span
                    v-if="org.is_default"
                    class="inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900/20 dark:text-blue-400">
                    {{ t('web.organizations.default') }}
                  </span>
                </div>
              </div>

              <!-- Stats row: Plan, Members, Domains -->
              <div class="mt-3 flex flex-wrap items-center gap-4 text-sm">
                <!-- Plan (links to billing if enabled) -->
                <router-link
                  v-if="billingEnabled && org.extid"
                  :to="`/billing/${org.extid}/overview`"
                  class="inline-flex items-center gap-1.5 text-gray-500 hover:text-brand-600 dark:text-gray-400 dark:hover:text-brand-400"
                  @click.stop>
                  <OIcon
                    collection="heroicons"
                    name="credit-card"
                    class="size-4"
                    aria-hidden="true" />
                  <span>{{ getOrgPlanName(org) }}</span>
                </router-link>
                <span
                  v-else
                  class="inline-flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
                  <OIcon
                    collection="heroicons"
                    name="credit-card"
                    class="size-4"
                    aria-hidden="true" />
                  <span>{{ getOrgPlanName(org) }}</span>
                </span>

                <!-- Members (links to members page) -->
                <router-link
                  v-if="org.extid"
                  :to="`/org/${org.extid}/members`"
                  class="inline-flex items-center gap-1.5 text-gray-500 hover:text-brand-600 dark:text-gray-400 dark:hover:text-brand-400"
                  @click.stop>
                  <OIcon
                    collection="heroicons"
                    name="users"
                    class="size-4"
                    aria-hidden="true" />
                  <span>{{ t('web.organizations.member_count', { count: org.member_count ?? 1 }) }}</span>
                </router-link>

                <!-- Domains (links to org-scoped domains page) -->
                <router-link
                  v-if="org.extid"
                  :to="`/org/${org.extid}/domains`"
                  class="inline-flex items-center gap-1.5 text-gray-500 hover:text-brand-600 dark:text-gray-400 dark:hover:text-brand-400"
                  @click.stop>
                  <OIcon
                    collection="heroicons"
                    name="globe-alt"
                    class="size-4"
                    aria-hidden="true" />
                  <span>{{ t('web.organizations.domain_count', { count: org.domain_count ?? 0 }) }}</span>
                </router-link>
              </div>
            </div>
          </div>

          <!-- Empty State -->
          <div v-else class="py-12 text-center">
            <OIcon
              collection="ph"
              name="building-office-bold"
              class="mx-auto size-12 text-gray-400"
              aria-hidden="true" />
            <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
              {{ t('web.organizations.no_organizations') }}
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.no_organizations_description') }}
            </p>
            <div class="mt-6">
              <button
                @click="handleCreateOrganization"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="plus"
                  class="size-4"
                  aria-hidden="true" />
                {{ t('web.organizations.create_first_organization') }}
              </button>
            </div>
          </div>
        </div>
      </section>

      <!-- Info Section - Personalized based on user entitlements -->
      <section
        v-if="isSingleUserAccount && hasOrganizations"
        class="rounded-lg border border-blue-200 bg-blue-50 p-6 dark:border-blue-900/50 dark:bg-blue-900/10">
        <div class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
            aria-hidden="true" />
          <div class="text-sm">
            <h3 class="font-medium text-blue-900 dark:text-blue-300">
              {{ t('web.organizations.single_user_info_title') }}
            </h3>
            <p class="mt-1 text-blue-700 dark:text-blue-400">
              {{ t('web.organizations.single_user_info_description') }}
            </p>
          </div>
        </div>
      </section>

      <section
        v-else-if="canCreateMultipleOrgs"
        class="rounded-lg border border-blue-200 bg-blue-50 p-6 dark:border-blue-900/50 dark:bg-blue-900/10">
        <div class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
            aria-hidden="true" />
          <div class="text-sm">
            <h3 class="font-medium text-blue-900 dark:text-blue-300">
              {{ t('web.organizations.about_title') }}
            </h3>
            <p class="mt-1 text-blue-700 dark:text-blue-400">
              {{ t('web.organizations.about_description') }}
            </p>
          </div>
        </div>
      </section>

      <section
        v-else-if="!hasOrganizations"
        class="rounded-lg border border-blue-200 bg-blue-50 p-6 dark:border-blue-900/50 dark:bg-blue-900/10">
        <div class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
            aria-hidden="true" />
          <div class="text-sm">
            <h3 class="font-medium text-blue-900 dark:text-blue-300">
              {{ t('web.organizations.getting_started_title') }}
            </h3>
            <p class="mt-1 text-blue-700 dark:text-blue-400">
              {{ t('web.organizations.getting_started_description') }}
            </p>
          </div>
        </div>
      </section>
    </div>

    <!-- Create Organization Modal -->
    <CreateOrganizationModal
      :open="showCreateModal"
      @close="showCreateModal = false"
      @created="handleOrganizationCreated" />
  </div>
</template>
