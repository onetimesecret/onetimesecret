<!-- src/apps/workspace/domains/DomainSignin.vue -->

<script setup lang="ts">
/**
 * Domain Sign-In Configuration Page
 *
 * Page-level component that wires together the signin config composable and
 * form component. Controls which auth methods are available on the
 * domain's signin page: password, email_auth, webauthn, SSO, or restrict
 * to a single method.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted } from 'vue';
import { useRouter, onBeforeRouteLeave } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainSigninConfigForm from '@/apps/workspace/components/domains/DomainSigninConfigForm.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useSigninConfig } from '@/shared/composables/useSigninConfig';
import { useOrganizationStore } from '@/shared/stores/organizationStore';

const { t } = useI18n();
const router = useRouter();

const props = defineProps<{
  orgid: string;
  extid: string;
}>();

// ---------------------------------------------------------------------------
// Domain data
// ---------------------------------------------------------------------------

const {
  domain: customDomainRecord,
  isLoading: domainLoading,
  error: domainError,
  initialize: initializeDomain,
} = useDomain(props.extid);

// ---------------------------------------------------------------------------
// Organization
// ---------------------------------------------------------------------------

const organizationStore = useOrganizationStore();
const { organizations } = storeToRefs(organizationStore);
const _organization = computed(() =>
  organizations.value.find((o) => o.extid === props.orgid) ?? null
);

// ---------------------------------------------------------------------------
// Signin config composable
// ---------------------------------------------------------------------------

const {
  isLoading: signinLoading,
  isInitialized: _isInitialized,
  isSaving,
  isDeleting,
  error: signinError,
  signinConfig: _signinConfig,
  formState,
  isConfigured,
  hasUnsavedChanges,
  initialize: initializeSigninConfig,
  saveConfig,
  deleteConfig,
  discardChanges,
} = useSigninConfig(props.extid);

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains/${props.extid}`);
};

// Unsaved changes guard
onBeforeRouteLeave((_to, _from, next) => {
  if (hasUnsavedChanges.value) {
    const answer = window.confirm(t('web.branding.you_have_unsaved_changes_are_you_sure'));
    if (answer) next();
    else next(false);
  } else {
    next();
  }
});

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

onMounted(async () => {
  await initializeDomain();
  await initializeSigninConfig();
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Back button -->
    <div class="mx-auto max-w-4xl px-4 pt-4 sm:px-6 lg:px-8">
      <div class="mb-4">
        <button
          type="button"
          class="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          @click="handleBack">
          <OIcon
            collection="heroicons"
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
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/signin" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <SettingsSkeleton v-if="domainLoading || signinLoading" />

      <!-- Error State -->
      <div v-else-if="domainError || signinError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="(domainError?.message ?? signinError?.message) ?? ''" />
      </div>

      <!-- Signin Configuration Form -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="arrow-right-on-rectangle"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.domains.signin.title') }}
              </h2>
              <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.domains.signin.config_description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="space-y-6 p-6">
          <!-- Not configured notice -->
          <div
            v-if="!isConfigured"
            class="flex items-start gap-3 rounded-md bg-blue-50 px-4 py-3 dark:bg-blue-900/20">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="mt-0.5 size-5 flex-shrink-0 text-blue-500 dark:text-blue-400"
              aria-hidden="true" />
            <p class="flex-1 text-sm text-blue-700 dark:text-blue-300">
              {{ t('web.domains.signin.not_configured_notice') }}
            </p>
          </div>

          <DomainSigninConfigForm
            :domain-ext-id="props.extid"
            v-model:form-state="formState"
            :is-loading="signinLoading"
            :is-saving="isSaving"
            :is-deleting="isDeleting"
            :has-unsaved-changes="hasUnsavedChanges"
            :is-configured="isConfigured"
            @save="saveConfig"
            @delete="deleteConfig"
            @discard="discardChanges" />
        </div>
      </div>
    </div>
  </div>
</template>
