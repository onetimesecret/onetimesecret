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
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import { useDomain } from '@/shared/composables/useDomain';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import {
  isOrgsSsoEnabled,
  isOrgsCustomMailEnabled,
  isOrgsIncomingSecretsEnabled,
} from '@/utils/features';
import { storeToRefs } from 'pinia';
import { computed, onMounted } from 'vue';

const { t } = useI18n();

const props = defineProps<{ extid: string; orgid: string }>();

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

interface Section {
  key: string;
  route: { name: string; params: { orgid: string; extid: string } };
  icon: { collection: string; name: string };
  titleKey: string;
  descriptionKey: string;
  available: boolean;
  locked: boolean;
}

const sections = computed<Section[]>(() => [
  {
    key: 'verify',
    route: { name: 'DomainVerify', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'shield-check' },
    titleKey: 'web.domains.verify_domain',
    descriptionKey: 'web.domains.detail.verify_description',
    available: true,
    locked: false,
  },
  {
    key: 'brand',
    route: { name: 'DomainBrand', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'paint-brush' },
    titleKey: 'web.domains.manage_brand',
    descriptionKey: 'web.domains.detail.brand_description',
    available: true,
    locked: !canBrand.value,
  },
  {
    key: 'sso',
    route: { name: 'DomainSso', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'key' },
    titleKey: 'web.domains.sso.configure_sso',
    descriptionKey: 'web.domains.detail.sso_description',
    available: isOrgsSsoEnabled(),
    locked: !canManageSso.value,
  },
  {
    key: 'email',
    route: { name: 'DomainEmail', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'envelope' },
    titleKey: 'web.domains.email.configure_email',
    descriptionKey: 'web.domains.detail.email_description',
    available: isOrgsCustomMailEnabled(),
    locked: !canEmailConfig.value,
  },
  {
    key: 'incoming',
    route: { name: 'DomainIncoming', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'inbox-arrow-down' },
    titleKey: 'web.domains.incoming.configure_incoming',
    descriptionKey: 'web.domains.detail.incoming_description',
    available: isOrgsIncomingSecretsEnabled(),
    locked: !canIncomingSecrets.value,
  },
]);

const visibleSections = computed(() => sections.value.filter((s) => s.available));

onMounted(() => {
  initializeDomain();
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        v-if="!domainLoading"
        :domain="customDomainRecord"
        :has-unsaved-changes="false"
        :orgid="props.orgid" />
    </div>

    <!-- Card grid -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <h2 class="mb-6 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.domains.detail.configuration') }}
      </h2>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <template
          v-for="section in visibleSections"
          :key="section.key">
          <!-- Unlocked: clickable RouterLink card -->
          <RouterLink
            v-if="!section.locked"
            :to="section.route"
            class="group relative rounded-lg border border-gray-200 bg-white p-5 transition-shadow hover:shadow-md dark:border-gray-700 dark:bg-gray-800">
            <OIcon
              :collection="section.icon.collection"
              :name="section.icon.name"
              class="mb-3 size-6 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <h3 class="font-brand text-sm font-semibold text-gray-900 dark:text-white">
              {{ t(section.titleKey) }}
            </h3>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {{ t(section.descriptionKey) }}
            </p>
            <OIcon
              collection="heroicons"
              name="arrow-right"
              class="absolute right-4 top-1/2 size-4 -translate-y-1/2 text-gray-300 transition-colors group-hover:text-brand-500 dark:text-gray-600 dark:group-hover:text-brand-400"
              aria-hidden="true" />
          </RouterLink>

          <!-- Locked: non-clickable card with upgrade hint -->
          <div
            v-else
            class="relative rounded-lg border border-gray-200 bg-gray-50 p-5 dark:border-gray-700 dark:bg-gray-800/50">
            <OIcon
              :collection="section.icon.collection"
              :name="section.icon.name"
              class="mb-3 size-6 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            <h3 class="font-brand text-sm font-semibold text-gray-500 dark:text-gray-400">
              {{ t(section.titleKey) }}
            </h3>
            <p class="mt-1 text-xs text-gray-400 dark:text-gray-500">
              {{ t(section.descriptionKey) }}
            </p>
            <OIcon
              collection="heroicons"
              name="lock-closed"
              class="absolute right-4 top-1/2 size-4 -translate-y-1/2 text-gray-300 dark:text-gray-600"
              aria-hidden="true" />
            <RouterLink
              :to="`/billing/${props.orgid}/plans`"
              class="mt-3 inline-flex items-center gap-1 text-xs font-medium text-amber-600 hover:text-amber-700 dark:text-amber-400 dark:hover:text-amber-300">
              {{ t('web.billing.overview.view_plans_action') }}
              <OIcon
                collection="heroicons"
                name="arrow-right"
                class="size-3"
                aria-hidden="true" />
            </RouterLink>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
