<!-- src/apps/workspace/domains/DomainSso.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainSsoConfigForm from '@/apps/workspace/components/domains/DomainSsoConfigForm.vue';
import { useDomain } from '@/shared/composables/useDomain';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import { storeToRefs } from 'pinia';

const { t } = useI18n();
const router = useRouter();

const props = defineProps<{
  orgid: string;
  extid: string;
}>();

// Domain data
const {
  domain: customDomainRecord,
  isLoading: domainLoading,
  error: domainError,
  initialize: initializeDomain,
} = useDomain(props.extid);

const displayDomain = computed(() => customDomainRecord.value?.display_domain ?? '');

// Entitlements check
const organizationStore = useOrganizationStore();
const { organizations } = storeToRefs(organizationStore);
const organization = computed(() =>
  organizations.value.find((o) => o.extid === props.orgid) ?? null
);
const { can } = useEntitlements(organization);
const canManageSso = computed(() => can(ENTITLEMENTS.MANAGE_SSO));

// Local state
const success = ref('');

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains`);
};

onMounted(() => {
  initializeDomain();
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
    <div class="border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="mx-auto max-w-4xl px-4 py-6 sm:px-6 lg:px-8">
        <div class="flex items-center gap-4">
          <button
            type="button"
            class="flex items-center gap-2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            @click="handleBack">
            <OIcon
              collection="heroicons"
              name="arrow-left"
              class="size-5"
              aria-hidden="true" />
            <span class="sr-only">{{ t('web.COMMON.back') }}</span>
          </button>
          <div>
            <h1 class="text-xl font-semibold text-gray-900 dark:text-white">
              {{ t('web.domains.sso.title') }}
            </h1>
            <p
              v-if="!domainLoading && displayDomain"
              class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ displayDomain }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <div v-if="domainLoading" class="flex items-center justify-center py-12">
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

      <!-- Error State -->
      <div v-else-if="domainError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="domainError.message" />
      </div>

      <!-- Access Denied -->
      <div
        v-else-if="!canManageSso"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.sso.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.sso.access_denied_description') }}
        </p>
      </div>

      <!-- SSO Configuration Form -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="shield-check"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 class="text-base font-semibold text-gray-900 dark:text-white">
                {{ t('web.domains.sso.config_title') }}
              </h2>
              <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.domains.sso.config_description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6">
          <DomainSsoConfigForm
            :domain-ext-id="props.extid"
            @saved="(isUpdate: boolean) => success = t(isUpdate ? 'web.domains.sso.update_success' : 'web.domains.sso.create_success')"
            @deleted="success = t('web.domains.sso.delete_success')" />
          <BasicFormAlerts
            v-if="success"
            :success="success"
            class="mt-6" />
        </div>
      </div>
    </div>
  </div>
</template>
