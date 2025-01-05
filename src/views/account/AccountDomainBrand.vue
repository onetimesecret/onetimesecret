<script setup lang="ts">
import BrandSettingsBar from '@/components/account/BrandSettingsBar.vue';
import BrowserPreviewFrame from '@/components/account/BrowserPreviewFrame.vue';
import DomainHeader from '@/components/account/DomainHeader.vue';
import InstructionsModal from '@/components/account/InstructionsModal.vue';
import SecretPreview from '@/components/account/SecretPreview.vue';
import LoadingOverlay from '@/components/common/LoadingOverlay.vue';
import { useBranding } from '@/composables/useBranding';
import type { CustomDomain } from '@/schemas/models';
import { Icon } from '@iconify/vue';
import { computed, onMounted, ref } from 'vue';
import { onBeforeRouteLeave, useRoute } from 'vue-router';

const props = defineProps<{ domain: string }>();
const {
  brand,
  brandSettings,
  loading,
  error,
  hasUnsavedChanges,
  logoImage,
  fetchBranding,
  submitBrandSettings,
  handleLogoUpload,
  detectPlatform,
  removeLogo,
  primaryColor,
} = useBranding(props.domain);

const route = useRoute();

const displayDomain = computed(() => `${props.domain || route.params.domain as string}`);
const customDomain = ref<CustomDomain | null>(null);
const color = computed(() => primaryColor.value);

const selectedBrowserType = ref<'safari' | 'edge'>(detectPlatform());

const toggleBrowser = () => {
  selectedBrowserType.value = selectedBrowserType.value === 'safari' ? 'edge' : 'safari';
};

onMounted(() => {
  fetchBranding();
  console.log("brandSettings", brandSettings.value)
});

// Only keep navigation guards and browser preview logic in component
onBeforeRouteLeave((to, from, next) => {
  if (hasUnsavedChanges.value) {
    const answer = window.confirm('You have unsaved changes. Are you sure?');
    if (answer) next();
    else next(false);
  } else {
    next();
  }
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader :display-domain="displayDomain"
                    :domain="customDomain" />

      <BrandSettingsBar v-model="brand"
                        :is-submitting="loading"
                        @submit="submitBrandSettings">
        <template #instructions-button>
          <InstructionsModal v-model="brandSettings.instructions_pre_reveal"
                             @update:model-value="(value) => brandSettings.instructions_pre_reveal = value" />
        </template>
      </BrandSettingsBar>
    </div>

    <!-- Main Content -->
    <div class="mx-auto max-w-7xl p-4 sm:px-6 sm:py-8 lg:px-8">
      <!-- Preview Section -->
      <div class="relative mb-6 sm:mb-12">
        <h2 id="previewHeading"
            class="mb-6 text-xl font-semibold text-gray-900 dark:text-gray-100">
          Preview & Customize
        </h2>

        <!-- Instructions for screen readers -->
        <div class="sr-only"
             role="note">
          This is an interactive preview of how recipients will see your secure messages. You can:
          - Customize colors and fonts using the controls above
          - Upload a logo (minimum 128x128 pixels recommended, 1MB max)
          - Test the preview using the "View Secret" button
        </div>

        <!-- Visual instructions -->
        <ul class="mb-4 space-y-1 text-sm sm:mb-6 sm:space-y-2"
            :aria-hidden="true">
          <li class="flex items-center gap-2">
            <Icon icon="mdi:palette-outline"
                  class="size-5"
                  aria-label="Customization icon" />
            Use the controls above to customize brand color, styles, and recipient instructions
          </li>

          <li class="flex items-center gap-2">
            <Icon icon="mdi:image-outline"
                  class="size-5"
                  aria-label="Image icon" />
            Click the preview image below to update your logo (minimum 128x128 pixels recommended, 1MB max)
          </li>

          <li class="flex items-center gap-2">
            <Icon icon="mdi:eye-outline"
                  class="size-5"
                  aria-label="Eye icon" />
            Preview how recipients will see your secrets by testing the "View Secret" button
          </li>
        </ul>

        <BrowserPreviewFrame class="mx-auto w-full max-w-3xl overflow-hidden"
                             :domain="displayDomain"
                             :browser-type="selectedBrowserType"
                             @toggle-browser="toggleBrowser"
                             aria-labelledby="previewHeading">
          <div class=" z-50 h-1 w-full"
               :style="{ backgroundColor: color }"></div>
          <SecretPreview v-if="!loading && !error"
                         ref="secretPreview"
                         :domain-branding="brandSettings"
                         :logo-image="logoImage"
                         :on-logo-upload="handleLogoUpload"
                         :on-logo-remove="removeLogo"
                         secret-key="abcd"
                         class="max-w-full transition-all duration-200 hover:scale-[1.02]" />
        </BrowserPreviewFrame>

        <!-- Loading and Error States -->
        <div v-if="loading"
             role="status"
             class="py-8 text-center">
          <span class="sr-only">Loading preview...</span>
          <!-- Add loading spinner -->
        </div>

        <div v-if="error"
             role="alert"
             class="py-8 text-center text-red-600">
          {{ error }}
        </div>
      </div>
    </div>


    <!-- Loading Overlay -->
    <LoadingOverlay :show="loading"
                    message="Loading brand settings" />
  </div>
</template>
