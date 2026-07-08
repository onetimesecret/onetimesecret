<!-- src/apps/workspace/domains/DomainBrand.vue -->

<script setup lang="ts">
  import BrandEditor from '@/apps/workspace/components/dashboard/brand/BrandEditor.vue';
  import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
  import InstructionsModal from '@/apps/workspace/components/dashboard/InstructionsModal.vue';
  import LanguageSelector from '@/apps/workspace/components/dashboard/LanguageSelector.vue';
  import { createError } from '@/schemas/errors';
  import LoadingOverlay from '@/shared/components/common/LoadingOverlay.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useBranding } from '@/shared/composables/useBranding';
  import { useDomain } from '@/shared/composables/useDomain';
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { ENTITLEMENTS } from '@/types/organization';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter, onBeforeRouteLeave } from 'vue-router';

  const { t } = useI18n(); // auto-import
  const router = useRouter();

  const props = defineProps<{ extid: string; orgid: string }>();

  const handleBack = () => {
    router.push(`/org/${props.orgid}/domains/${props.extid}`);
  };
  const {
    isLoading,
    error,
    brandSettings,
    logoImage,
    previewI18n,
    hasUnsavedChanges,
    isInitialized,
    initialize: initializeBrand,
    saveBranding,
    handleLogoUpload,
    removeLogo,
  } = useBranding(props.extid);

  const {
    domain: customDomainRecord,
    initialize: initializeDomain,
  } = useDomain(props.extid);

  const displayDomain = computed(() => customDomainRecord.value?.display_domain);

  const bootstrapStore = useBootstrapStore();
  const { i18n_enabled } = storeToRefs(bootstrapStore);

  const organizationStore = useOrganizationStore();
  const { organizations } = storeToRefs(organizationStore);
  const organization = computed(() =>
    organizations.value.find((o) => o.extid === props.orgid) ?? null
  );
  const { can } = useEntitlements(organization);
  const canBrand = computed(() => can(ENTITLEMENTS.CUSTOM_BRANDING));

  const isSaveDisabled = computed(() => isLoading.value || !hasUnsavedChanges.value);

  // Instructions fields configuration for the modal
  const instructionFields = computed(() => [
    {
      key: 'instructions_pre_reveal',
      label: t('web.branding.pre_reveal_instructions'),
      tooltipContent: t('web.branding.these_instructions_will_be_shown_to_recipients_before'),
      placeholderKey: t('web.branding.example_pre_reveal_instructions'),
      value: brandSettings.value?.instructions_pre_reveal || ''
    },
    {
      key: 'instructions_post_reveal',
      label: t('web.branding.post_reveal_instructions'),
      tooltipContent: t('web.branding.these_instructions_will_be_shown_to_recipients_after'),
      placeholderKey: t('web.branding.example_post_reveal_instructions'),
      value: brandSettings.value?.instructions_post_reveal || ''
    }
  ]);

  // Handle instruction updates from the modal
  const handleInstructionUpdate = (key: string, value: string) => {
    if (brandSettings.value) {
      brandSettings.value = {
        ...brandSettings.value,
        [key]: value
      };
    }
  };

  // Add loading guard
  watch(
    () => isLoading.value,
    (loading) => {
      if (!loading && !brandSettings.value) {
        error.value = createError(t('web.branding.failed_to_load_brand_settings'), 'technical', 'error');
      }
    }
  );

  onMounted(() => {
    initializeBrand();
    initializeDomain();
  });

  onBeforeRouteLeave((to, from, next) => {
    if (hasUnsavedChanges.value) {
      const answer = window.confirm(t('web.branding.you_have_unsaved_changes_are_you_sure'));
      if (answer) next();
      else next(false);
    } else {
      next();
    }
  });
</script>

<template>
  <div>
    <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
      <!-- Back button -->
      <div class="mx-auto max-w-7xl px-4 pt-4 sm:px-6 lg:px-8">
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
          external-path="/" />

        <!-- Save action bar (replaces the old BrandSettingsBar's save button) -->
        <div
          v-if="canBrand"
          class="border-b border-gray-200 bg-white/80 backdrop-blur-sm dark:border-gray-700 dark:bg-gray-800/80">
          <div class="mx-auto flex max-w-7xl justify-end px-4 py-2.5 sm:px-6 lg:px-8">
            <!-- prettier-ignore-attribute class -->
            <button
              type="button"
              :disabled="isSaveDisabled"
              @click="saveBranding(brandSettings)"
              class="inline-flex h-11 min-w-[120px] shrink-0 items-center
                justify-center rounded-lg border border-transparent
                bg-brand-600 px-4 text-base font-medium text-white shadow-sm
                transition-all duration-200 hover:bg-brand-700 focus:ring-2
                focus:ring-brand-500 focus:ring-offset-2 focus:outline-none
                disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm
                dark:focus:ring-brand-400 dark:focus:ring-offset-0">
              <OIcon
                v-if="isLoading"
                collection="mdi"
                name="loading"
                class="mr-2 -ml-1 size-4 animate-spin motion-reduce:animate-none" />
              <OIcon
                v-else
                collection="mdi"
                name="content-save"
                class="mr-2 -ml-1 size-4" />
              {{ isLoading ? t('web.LABELS.saving') : t('web.LABELS.save') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Upgrade banner when custom_branding entitlement is missing -->
      <div
        v-if="!canBrand"
        class="mx-auto mt-8 max-w-3xl px-4 sm:px-6 lg:px-8">
        <div class="flex items-center gap-3 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 flex-shrink-0 text-amber-500 dark:text-amber-400"
            aria-hidden="true" />
          <p class="flex-1 text-sm text-amber-700 dark:text-amber-300">
            {{ t('web.branding.upgrade_to_customize') }}
          </p>
          <RouterLink
            :to="`/billing/${props.orgid}/plans`"
            class="inline-flex items-center gap-1 text-sm font-medium text-amber-700 hover:text-amber-800 dark:text-amber-300 dark:hover:text-amber-200">
            {{ t('web.billing.overview.view_plans_action') }}
            <OIcon
              collection="heroicons"
              name="arrow-right"
              class="size-4"
              aria-hidden="true" />
          </RouterLink>
        </div>
      </div>

      <!-- Main Content. Gated on isInitialized (set true after the first load
           and never reset) rather than !isLoading, so a Save — which flips
           isLoading during its request — never unmounts the editor and resets
           the active path / disclosures. LoadingOverlay covers the save. -->
      <div
        v-if="canBrand && isInitialized"
        class="mx-auto max-w-7xl p-4 sm:px-6 sm:py-8 lg:px-8">
        <h2
          id="previewHeading"
          class="mb-6 text-xl font-semibold text-gray-900 dark:text-gray-100">
          {{ t('web.branding.preview_and_customize') }}
        </h2>

        <!-- Three-path editor + fixed preview -->
        <BrandEditor
          v-model="brandSettings"
          :logo-image="logoImage"
          :preview-i18n="previewI18n"
          :on-logo-upload="handleLogoUpload"
          :on-logo-remove="removeLogo"
          :display-domain="displayDomain" />

        <!-- Recipient page content (language + reveal instructions). A future
             "Delivery" tab will rehome these; kept here for now so nothing is
             orphaned. -->
        <div class="mt-8 rounded-2xl border border-gray-200 bg-white p-[18px] dark:border-gray-700 dark:bg-gray-800">
          <h3 class="font-brand-slab text-base font-bold text-gray-900 dark:text-gray-100">
            {{ t('web.branding.recipient_page_content') }}
          </h3>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.branding.recipient_page_content_hint') }}
          </p>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <InstructionsModal
              :instruction-fields="instructionFields"
              :preview-i18n="previewI18n"
              @update="handleInstructionUpdate"
              @save="() => saveBranding(brandSettings)" />
            <LanguageSelector
              v-if="i18n_enabled"
              v-model="brandSettings.locale"
              :preview-i18n="previewI18n"
              @update:model-value="(value) => (brandSettings.locale = value)" />
          </div>
        </div>
      </div>

      <!-- Loading Overlay -->
      <LoadingOverlay
        :show="isLoading"
        message="Loading brand settings" />
    </div>
  </div>
</template>
