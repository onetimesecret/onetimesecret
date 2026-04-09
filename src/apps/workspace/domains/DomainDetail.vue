<!-- src/apps/workspace/domains/DomainDetail.vue -->

<script setup lang="ts">
/**
 * Domain Detail Hub Page
 *
 * Navigation hub showing all available configuration sections for a domain.
 * Each section is displayed as a card linking to its dedicated page.
 * Entitlement-gated sections show a lock icon and upgrade link.
 */
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import { useDomain } from '@/shared/composables/useDomain';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { ENTITLEMENTS } from '@/types/organization';
import {
  isOrgsSsoEnabled,
  isOrgsCustomMailEnabled,
  isOrgsIncomingSecretsEnabled,
} from '@/utils/features';
import { storeToRefs } from 'pinia';
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';

const { t } = useI18n();
const router = useRouter();

const props = defineProps<{ extid: string; orgid: string }>();

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains`);
};

const {
  domain: customDomainRecord,
  isLoading: domainLoading,
  initialize: initializeDomain,
} = useDomain(props.extid);

const organizationStore = useOrganizationStore();
const { organizations } = storeToRefs(organizationStore);
const organization = computed(() =>
  organizations.value.find((o) => o.extid === props.orgid) ?? null
);
const { can } = useEntitlements(organization);

const canBrand = computed(() => can(ENTITLEMENTS.CUSTOM_BRANDING));
const canManageSso = computed(() => can(ENTITLEMENTS.MANAGE_SSO));
const canEmailConfig = computed(() => can(ENTITLEMENTS.CUSTOM_MAIL_SENDER));
const canIncomingSecrets = computed(() => can(ENTITLEMENTS.INCOMING_SECRETS));

/** Current user is owner or admin — can modify domain settings */
const canAdmin = computed(() => {
  const role = organization.value?.current_user_role;
  return role === 'owner' || role === 'admin';
});

const domainsStore = useDomainsStore();

const handleHomepageToggle = async () => {
  const domain = customDomainRecord.value;
  if (!domain) return;
  const newValue = !domain.brand?.allow_public_homepage;
  await domainsStore.updateDomainBrand(domain.extid, {
    brand: { allow_public_homepage: newValue },
  });
  // Refresh domain data to reflect the change
  await initializeDomain();
};

interface Section {
  key: string;
  route: { name: string; params: { orgid: string; extid: string } } | null;
  icon: { collection: string; name: string };
  titleKey: string;
  descriptionKey: string;
  available: boolean;
  locked: boolean;
  /** When true, show an enable/disable toggle instead of a navigation arrow */
  toggleable: boolean;
  /** Current toggle state (only used when toggleable is true) */
  enabled: boolean;
}

const sections = computed<Section[]>(() => [
  {
    key: 'homepage',
    route: null,
    icon: { collection: 'heroicons', name: 'home' },
    titleKey: 'web.domains.detail.homepage_title',
    descriptionKey: 'web.domains.detail.homepage_description',
    available: true,
    locked: false,
    toggleable: true,
    enabled: customDomainRecord.value?.brand?.allow_public_homepage ?? false,
  },
  {
    key: 'brand',
    route: { name: 'DomainBrand', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'paint-brush' },
    titleKey: 'web.domains.manage_brand',
    descriptionKey: 'web.domains.detail.brand_description',
    available: true,
    locked: !canBrand.value,
    toggleable: false,
    enabled: false,
  },
  {
    key: 'sso',
    route: { name: 'DomainSso', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'key' },
    titleKey: 'web.domains.sso.configure_sso',
    descriptionKey: 'web.domains.detail.sso_description',
    available: isOrgsSsoEnabled(),
    locked: !canManageSso.value,
    toggleable: false,
    enabled: false,
  },
  {
    key: 'incoming',
    route: { name: 'DomainIncoming', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'inbox-arrow-down' },
    titleKey: 'web.domains.incoming.configure_incoming',
    descriptionKey: 'web.domains.detail.incoming_description',
    available: isOrgsIncomingSecretsEnabled(),
    locked: !canIncomingSecrets.value,
    toggleable: false,
    enabled: false,
  },
  {
    key: 'email',
    route: { name: 'DomainEmail', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'envelope' },
    titleKey: 'web.domains.email.configure_email',
    descriptionKey: 'web.domains.detail.email_description',
    available: isOrgsCustomMailEnabled(),
    locked: !canEmailConfig.value,
    toggleable: false,
    enabled: false,
  },
]);

const visibleSections = computed(() => sections.value.filter((s) => s.available));

onMounted(() => {
  initializeDomain();
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Back button -->
    <div class="mx-auto max-w-7xl px-4 pt-4 sm:px-6 lg:px-8">
      <div class="mb-4">
        <button
          type="button"
          class="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          @click="handleBack">
          <OIcon collection="heroicons"
name="arrow-left"
class="size-5"
aria-hidden="true" />
          {{ t('web.COMMON.back') }}
        </button>
      </div>
    </div>

    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        v-if="!domainLoading"
        :domain="customDomainRecord"
        :has-unsaved-changes="false"
        :orgid="props.orgid" />
    </div>

    <!-- Features list -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <h2 class="mb-6 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.domains.detail.features') }}
      </h2>

      <div class="divide-y divide-gray-200 rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-800">
        <template
          v-for="section in visibleSections"
          :key="section.key">
          <!-- Unlocked: feature row with toggle or navigation -->
          <component
            :is="section.route && !section.locked ? 'RouterLink' : 'div'"
            v-if="!section.locked"
            v-bind="section.route && !section.toggleable ? { to: section.route } : {}"
            :class="[
              'flex items-center justify-between gap-4 px-5 py-4',
              section.route && !section.toggleable ? 'group transition-colors hover:bg-gray-50 dark:hover:bg-gray-700/50' : '',
            ]">
            <div class="flex min-w-0 items-center gap-4">
              <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-900/20">
                <OIcon
                  :collection="section.icon.collection"
                  :name="section.icon.name"
                  class="size-5 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0">
                <h3 class="font-brand text-sm font-semibold text-gray-900 dark:text-white">
                  {{ t(section.titleKey) }}
                </h3>
                <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                  {{ t(section.descriptionKey) }}
                </p>
              </div>
            </div>
            <div class="flex shrink-0 items-center">
              <!-- Toggle for toggleable features (e.g. homepage) -->
              <ToggleWithIcon
                v-if="section.toggleable"
                :enabled="section.enabled"
                :disabled="domainLoading || !canAdmin"
                @update:enabled="handleHomepageToggle" />
              <!-- Arrow for navigable features -->
              <OIcon
                v-else
                collection="heroicons"
                name="chevron-right"
                class="size-5 text-gray-400 transition-colors group-hover:text-brand-500 dark:text-gray-500 dark:group-hover:text-brand-400"
                aria-hidden="true" />
            </div>
          </component>

          <!-- Locked: disabled row with upgrade hint -->
          <div
            v-else
            class="flex items-center justify-between gap-4 bg-gray-50/50 px-5 py-4 dark:bg-gray-800/50">
            <div class="flex min-w-0 items-center gap-4">
              <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-gray-100 dark:bg-gray-700">
                <OIcon
                  :collection="section.icon.collection"
                  :name="section.icon.name"
                  class="size-5 text-gray-400 dark:text-gray-500"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0">
                <h3 class="font-brand text-sm font-semibold text-gray-500 dark:text-gray-400">
                  {{ t(section.titleKey) }}
                </h3>
                <p class="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
                  {{ t(section.descriptionKey) }}
                </p>
              </div>
            </div>
            <div class="flex shrink-0 items-center gap-3">
              <RouterLink
                :to="`/billing/${props.orgid}/plans`"
                class="inline-flex items-center gap-1 text-xs font-medium text-amber-600 hover:text-amber-700 dark:text-amber-400 dark:hover:text-amber-300">
                {{ t('web.billing.overview.view_plans_action') }}
                <OIcon
                  collection="heroicons"
                  name="arrow-right"
                  class="size-3"
                  aria-hidden="true" />
              </RouterLink>
              <OIcon
                collection="heroicons"
                name="lock-closed"
                class="size-4 text-gray-300 dark:text-gray-600"
                aria-hidden="true" />
            </div>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
