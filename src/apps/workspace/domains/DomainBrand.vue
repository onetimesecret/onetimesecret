<!-- src/apps/workspace/domains/DomainBrand.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import LoadingOverlay from '@/shared/components/common/LoadingOverlay.vue';
  import BrandSettingsBar from '@/apps/workspace/components/dashboard/BrandSettingsBar.vue';
  import BrowserPreviewFrame from '@/apps/workspace/components/dashboard/BrowserPreviewFrame.vue';
  import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
  import InstructionsModal from '@/apps/workspace/components/dashboard/InstructionsModal.vue';
  import LanguageSelector from '@/apps/workspace/components/dashboard/LanguageSelector.vue';
  import SecretPreview from '@/apps/workspace/components/dashboard/SecretPreview.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useBranding } from '@/shared/composables/useBranding';
  import { useDomain } from '@/shared/composables/useDomain';
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import { createError } from '@/schemas/errors';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { ENTITLEMENTS } from '@/types/organization';
  import { storeToRefs } from 'pinia';
  import { detectPlatform } from '@/utils';
  import { computed, onMounted, ref, watch } from 'vue';
  import { onBeforeRouteLeave } from 'vue-router';

  const { t } = useI18n(); // auto-import

  const props = defineProps<{ extid: string; orgid: string }>();
  const {
    isLoading,
    error,
    brandSettings,
    logoImage,
    primaryColor,
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
    isLoading: domainLoading,
    initialize: initializeDomain,
  } = useDomain(props.extid);

  const displayDomain = computed(() => customDomainRecord.value?.display_domain);

  const color = computed(() => primaryColor.value ?? undefined);
  const browserType = ref<'safari' | 'edge'>(detectPlatform());

  const toggleBrowser = () => {
    browserType.value = browserType.value === 'safari' ? 'edge' : 'safari';
  };

  const upgradeBannerDismissed = ref(false);

  const bootstrapStore = useBootstrapStore();
  const { i18n_enabled } = storeToRefs(bootstrapStore);

  const organizationStore = useOrganizationStore();
  const { organizations } = storeToRefs(organizationStore);
  const organization = computed(() =>
    organizations.value.find((o) => o.extid === props.orgid) ?? null
  );
  const { can } = useEntitlements(organization);
  const canBrand = computed(() => can(ENTITLEMENTS.CUSTOM_BRANDING));

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
      <!-- Header Section -->
      <div class="sticky top-0 z-30">
        <DomainHeader
          v-if="!domainLoading"
          :domain="customDomainRecord"
          :has-unsaved-changes="hasUnsavedChanges"
          :orgid="props.orgid" />

        <BrandSettingsBar
          v-if="canBrand"
          v-model="brandSettings"
          :preview-i18n="previewI18n"
          :is-loading="isLoading"
          :is-initialized="isInitialized"
          :has-unsaved-changes="hasUnsavedChanges"
          :disabled="!canBrand"
          @submit="() => saveBranding(brandSettings)">
          <template
            v-if="canBrand"
            #instructions-buttons>
            <InstructionsModal
              :instruction-fields="instructionFields"
              :preview-i18n="previewI18n"
              @update="handleInstructionUpdate"
              @save="() => saveBranding(brandSettings)" />
          </template>

          <template
            v-if="canBrand"
            #language-button>
            <LanguageSelector
              v-if="i18n_enabled"
              v-model="brandSettings.locale"
              :preview-i18n="previewI18n"
              @update:model-value="(value) => (brandSettings.locale = value)" />
          </template>
        </BrandSettingsBar>
      </div>

      <!-- Upgrade banner when custom_branding entitlement is missing -->
      <div
        v-if="!canBrand && !upgradeBannerDismissed"
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
          <button
            type="button"
            class="ml-2 rounded p-1 text-amber-500 hover:bg-amber-100 hover:text-amber-700 dark:text-amber-400 dark:hover:bg-amber-900/40 dark:hover:text-amber-300"
            :aria-label="t('web.LABELS.close')"
            @click="upgradeBannerDismissed = true">
            <OIcon
              collection="heroicons"
              name="x-mark"
              class="size-4"
              aria-hidden="true" />
          </button>
        </div>
      </div>

      <!-- Main Content -->
      <div
        v-if="canBrand"
        class="mx-auto max-w-7xl p-4 sm:px-6 sm:py-8 lg:px-8">
        <!-- Preview Section -->
        <div class="relative mb-6 sm:mb-12">
          <h2
            id="previewHeading"
            class="mb-6 text-xl font-semibold text-gray-900 dark:text-gray-100">
            {{ t('web.branding.preview_and_customize') }}
          </h2>

          <!-- Instructions for screen readers -->
          <div
            class="sr-only"
            role="note">
            {{ t('web.branding.this_is_an_interactive_preview_of_how_recipients') }}
          </div>

          <!-- Visual instructions -->
          <ul
            class="mb-4 space-y-1 text-sm sm:mb-6 sm:space-y-2"
            :aria-hidden="true">
            <li class="flex items-center gap-2">
              <OIcon
                collection="mdi"
                name="palette-outline"
                class="size-5"
                :aria-label="t('web.branding.customization_icon')" />
              {{ t('web.branding.use_the_controls_above_to_customize_brand_details') }}
            </li>

            <li class="flex items-center gap-2">
              <OIcon
                collection="mdi"
                name="image-outline"
                class="size-5"
                :aria-label="t('web.branding.image_icon')" />
              {{ t('web.branding.click_the_preview_image_below_to_update_your_logo') }}
            </li>

            <li class="flex items-center gap-2">
              <OIcon
                collection="mdi"
                name="eye-outline"
                class="size-5"
                :aria-label="t('web.branding.eye_icon')" />
              {{ t('web.branding.preview_how_recipients_will_see_your_secrets') }}
            </li>
          </ul>

          <!-- Recipient Preview -->
          <BrowserPreviewFrame
            v-if="displayDomain"
            :domain="displayDomain"
            :browser-type="browserType"
            @toggle-browser="toggleBrowser"
            aria-labelledby="previewHeading">
            <div
              class="z-50 h-1 w-full"
              :style="{ backgroundColor: color }"></div>
            <SecretPreview
              v-if="!isLoading"
              ref="secretPreview"
              :domain-branding="brandSettings"
              :logo-image="logoImage"
              :preview-i18n="previewI18n"
              :on-logo-upload="canBrand ? handleLogoUpload : undefined"
              :on-logo-remove="canBrand ? removeLogo : undefined"
              secret-identifier="abcd"
              class="max-w-full transition-all duration-200 hover:scale-[1.02]" />
          </BrowserPreviewFrame>

          <!-- Loading and Error States -->
          <div
            v-if="isLoading"
            role="status"
            class="py-8 text-center">
            <span class="sr-only">{{ t('web.branding.loading_preview') }}</span>
            <!-- Add isLoading spinner -->
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
