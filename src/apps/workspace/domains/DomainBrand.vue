<!-- src/apps/workspace/domains/DomainBrand.vue -->

<script setup lang="ts">
  import BrandPreviewColumn from '@/apps/workspace/components/dashboard/brand/BrandPreviewColumn.vue';
  import SimpleBrandPanel from '@/apps/workspace/components/dashboard/brand/SimpleBrandPanel.vue';
  import DeliveryPanel from '@/apps/workspace/components/dashboard/DeliveryPanel.vue';
  import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
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
  import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
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
    faviconImage,
    previewI18n,
    hasUnsavedChanges,
    isInitialized,
    initialize: initializeBrand,
    saveBranding,
    handleLogoUpload,
    removeLogo,
    refreshFavicon,
    handleFaviconUpload,
    removeFavicon,
  } = useBranding(props.extid);

  const {
    domain: customDomainRecord,
    initialize: initializeDomain,
  } = useDomain(props.extid);

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

  // #3780: gate the "Refresh favicon" button. A forced fetch cannot overwrite a
  // user-uploaded icon (backend overwrite-guard), so the control is only
  // meaningful when the icon is empty or was auto-fetched. favicon_source rides
  // on the domain record's icon hashkey; absent (older payloads) → undefined →
  // button stays enabled and the backend guard remains the real protection.
  const faviconSource = computed<string | null | undefined>(
    () => customDomainRecord.value?.icon?.favicon_source ?? undefined
  );

  // Domain-settings tabs. Brand = the Simple brand panel; Delivery = the
  // recipient-facing language + reveal instructions (companion tab). Both tabs
  // edit the same brandSettings record and persist via the shared header Save,
  // so switching between them never loses work. Held here (inside the
  // isInitialized content block) rather than keyed on isLoading, so a Save —
  // which flips isLoading — never resets the active tab.
  const tabs = [
    { id: 'brand', labelKey: 'web.branding.tab_brand' },
    { id: 'delivery', labelKey: 'web.branding.tab_delivery' },
  ] as const;
  const activeTab = ref<'brand' | 'delivery'>('brand');

  // Reveal state of the persistent preview column, page-held so the Delivery
  // tab can drive it: focusing the post-reveal instructions field flips the
  // preview to the revealed state (and the pre-reveal field flips it back), so
  // the text being edited is the text on screen. The preview's own toggle
  // writes back through v-model:revealed.
  const previewRevealed = ref(false);

  // Add loading guard
  watch(
    () => isLoading.value,
    (loading) => {
      if (!loading && !brandSettings.value) {
        error.value = createError(t('web.branding.failed_to_load_brand_settings'), 'technical', 'error');
      }
    }
  );

  // Native navigations bypass Vue Router: the masthead logo is a hard <a href>
  // and the UserMenu has external <a href> items, so onBeforeRouteLeave (which
  // only guards in-app routing, e.g. the Back button) never fires for them.
  // A beforeunload listener catches those hard navigations — plus refresh and
  // tab close — while edits are pending, mirroring the in-app confirm below.
  const handleBeforeUnload = (event: BeforeUnloadEvent) => {
    if (!hasUnsavedChanges.value) return;
    event.preventDefault();
    // Legacy browsers require returnValue set to trigger the native prompt.
    event.returnValue = '';
  };

  onMounted(() => {
    initializeBrand();
    initializeDomain();
    window.addEventListener('beforeunload', handleBeforeUnload);
  });

  onUnmounted(() => {
    window.removeEventListener('beforeunload', handleBeforeUnload);
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
      <!-- Header Section. Back + title + Save share one row (opt-in DomainHeader
           affordances), so there's no separate Back row or Save action bar. -->
      <div class="sticky top-0 z-30">
        <DomainHeader
          :domain="customDomainRecord"
          :has-unsaved-changes="hasUnsavedChanges"
          :orgid="props.orgid"
          external-path="/"
          back-visible
          :save-visible="canBrand"
          :save-disabled="isSaveDisabled"
          :save-loading="isLoading"
          @back="handleBack"
          @save="saveBranding(brandSettings)" />
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
        <!-- Brand | Delivery tabs — both edit the same brandSettings record. -->
        <div
          class="mb-6 flex gap-6 border-b border-gray-200 dark:border-gray-700"
          role="tablist">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            type="button"
            role="tab"
            :aria-selected="activeTab === tab.id"
            @click="activeTab = tab.id"
            class="-mb-px border-b-2 px-1 pb-2.5 text-sm font-medium transition-colors focus:outline-none"
            :class="activeTab === tab.id
              ? 'border-brand-600 text-gray-900 dark:border-brand-400 dark:text-gray-100'
              : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'">
            {{ t(tab.labelKey) }}
          </button>
        </div>

        <!-- One page-level grid for both tabs: the left column swaps by tab
             while a single BrandPreviewColumn instance persists on the right
             (delivery locale + reveal instructions render on the recipient
             page too, and reveal state survives tab switches). The three-path
             switcher is hidden until Match/Advanced are built — only Simple
             ships — so SimpleBrandPanel mounts directly and BrandEditor /
             BrandPathSwitcher / the teasers sit unused. -->
        <div class="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
          <!-- Brand tab: the Simple path panel -->
          <SimpleBrandPanel
            v-if="activeTab === 'brand'"
            v-model="brandSettings"
            :logo-image="logoImage"
            :on-logo-upload="handleLogoUpload"
            :on-logo-remove="removeLogo"
            :favicon-image="faviconImage"
            :on-favicon-upload="handleFaviconUpload"
            :on-favicon-remove="removeFavicon"
            :on-refresh-favicon="refreshFavicon"
            :favicon-source="faviconSource" />

          <!-- Delivery tab: recipient-facing language + reveal instructions.
               Focus in an instruction field flips the preview to the matching
               reveal state. -->
          <DeliveryPanel
            v-else
            v-model="brandSettings"
            :i18n-enabled="i18n_enabled"
            :preview-i18n="previewI18n"
            @instructions-focus="(field) => (previewRevealed = field === 'post')" />

          <BrandPreviewColumn
            v-model:revealed="previewRevealed"
            :brand-settings="brandSettings"
            :logo-image="logoImage"
            :on-logo-upload="handleLogoUpload"
            :on-logo-remove="removeLogo"
            secret-identifier="abcd"
            :preview-i18n="previewI18n" />
        </div>
      </div>

      <!-- Loading Overlay -->
      <LoadingOverlay
        :show="isLoading"
        message="Loading brand settings" />
    </div>
  </div>
</template>
