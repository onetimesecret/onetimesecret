<!-- src/apps/workspace/components/dashboard/SecretPreview.vue -->

<script setup lang="ts">
import BaseSecretDisplay from '@/apps/secret/components/branded/BaseSecretDisplay.vue';
import { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ImageUploadModal from '@/shared/components/modals/ImageUploadModal.vue';
import { useLogoImage } from '@/shared/composables/useLogoImage';
import {
CornerStyle,
borderRadiusToCss,
cornerStyleClasses,
fontFamilyClasses,
resolveBodyFontClass,
resolveHeadingFontClass
} from '@/shared/utils/brand-helpers';
import { computed, ref } from 'vue';
import { Composer, useI18n } from 'vue-i18n';

const { t } = useI18n();

// The Tailwind @theme token that `rounded-brand` reads (border-radius: var(...)).
// Named so rootStyle scopes it by reference, not a repeated string literal.
const RADIUS_BRAND_VAR = '--radius-brand';

const props = defineProps<{
  domainBranding: BrandSettings;
  logoImage?: ImageProps | null;
  onLogoUpload: (file: File) => Promise<unknown>;
  onLogoRemove: () => Promise<unknown>;
  secretIdentifier: string;
  previewI18n: Composer;
}>();

// Logo validity + data-URL derivation shared with the Simple form's
// BrandLogoField (useLogoImage), so the two upload entry points can't drift.
const { isValidLogo, logoSrc } = useLogoImage(() => props.logoImage);

// Clicking the preview logo opens the shared staging modal (same as the Simple
// form's control) — the commit happens on the modal's confirm, not on pick.
const isLogoModalOpen = ref(false);

const isRevealed = ref(false);
const textareaPlaceholder = computed(() => props.previewI18n.t('web.secrets.sample_secret_content_this_could_be_sensitive_data'));

const ariaLabelText = computed(() =>
  isRevealed.value
    ? props.previewI18n.t('web.secrets.hide_secret_message')
    : props.previewI18n.t('web.secrets.view_secret_message')
)

const toggleReveal = () => {
  isRevealed.value = !isRevealed.value;
};

// Mirror identityStore.cornerClass: border_radius (#3646) supersedes corner_style
// when set. The recipient page backs `rounded-brand` with <html>'s injected
// --radius-brand; the preview can't use that (it's the operator's theme, not the
// edited domain), so it scopes --radius-brand locally via rootStyle below. Guard
// matches identityStore (`!= null && !== ''`) so an invalid-but-present radius
// falls back to the @theme default there too.
const cornerClass = computed(() => {
  const radius = props.domainBranding?.border_radius;
  if (radius != null && radius !== '') return 'rounded-brand';
  const style = props.domainBranding?.corner_style as CornerStyle | undefined;
  return cornerStyleClasses[style ?? CornerStyle.ROUNDED];
});

// The preview shows sans when the domain is unset because the dashboard page
// font differs from the recipient page ('' would inherit the dashboard font).
const fontFamilyClass = computed(
  () => resolveBodyFontClass(props.domainBranding) || fontFamilyClasses.sans
);

const headingFontClass = computed(
  () => resolveHeadingFontClass(props.domainBranding) || fontFamilyClasses.sans
);

// Expanded vocabulary (#3646). The preview renders an arbitrary domain's
// settings (not the editing admin's injected palette). Scope this domain's
// border_radius to a local --radius-brand so every `rounded-brand` descendant
// (logo, content box, textarea, button, and BaseSecretDisplay's content
// wrapper) resolves to THIS domain's radius — matching the recipient page.
// Applied on the wrapper that holds both the relocated logo AND the card, so
// the logo above the card inherits the same radius (custom properties cascade).
const rootStyle = computed<Record<string, string>>(() => {
  const css = borderRadiusToCss(props.domainBranding?.border_radius);
  const style: Record<string, string> = {};
  if (css) style[RADIUS_BRAND_VAR] = css;
  return style;
});

const actionButtonStyle = computed<Record<string, string>>(() => ({
  backgroundColor: props.domainBranding.primary_color ?? 'var(--color-brand-500)',
  color: (props.domainBranding.button_text_light ?? true) ? '#ffffff' : '#000000',
}));

</script>

<template>
  <!-- Scope the domain's corner-radius CSS var to the whole preview (logo + card)
       so the relocated logo above the card rounds to THIS domain, like the card. -->
  <div :style="rootStyle">
    <!-- Logo opener: mirrors the recipient page's logo-only BrandedHero (centered
         above the card, aspect-ratio-tolerant), but stays an interactive upload
         control — the preview's logo is editable, so keep the click-to-upload
         affordance and the empty-state prompt instead of hiding a missing logo. -->
    <div class="mb-3 flex justify-center pt-6">
      <div class="group relative">
        <button
          type="button"
          class="block cursor-pointer"
          :aria-label="t('web.branding.click_to_upload_a_logo_with_recommendation')"
          @click="isLogoModalOpen = true">
          <!-- With a logo: fixed height, auto width — wide/rectangular logos use
               the full width instead of being squished into a square. -->
          <img
            v-if="isValidLogo"
            :src="logoSrc"
            :alt="logoImage?.filename || t('web.layout.brand_logo')"
            :class="cornerClass"
            class="hover:ring-primary-500 h-16 w-auto max-w-full object-contain hover:ring-2 hover:ring-offset-2 sm:h-20" />
          <!-- Without a logo: a fixed placeholder tile that prompts an upload
               (wiggles for attention). The real page hides a missing logo; the
               preview must always offer the affordance. -->
          <div
            v-else
            :class="[cornerClass, 'animate-wiggle']"
            class="hover:ring-primary-500 flex size-16 items-center justify-center overflow-hidden bg-gray-100 hover:ring-2 hover:ring-offset-2 sm:size-20 dark:bg-gray-700">
            <svg
              class="size-8 text-gray-400 dark:text-gray-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </div>
        </button>

        <ImageUploadModal
          :is-open="isLogoModalOpen"
          :current-image="logoImage"
          :title="t('web.branding.logo_modal_title')"
          :hint="t('web.branding.logo_modal_hint')"
          :save-label="t('web.branding.logo_modal_save')"
          :remove-label="t('web.branding.remove_logo')"
          :on-save="onLogoUpload"
          :on-remove="onLogoRemove"
          @close="isLogoModalOpen = false" />
      </div>
    </div>

    <BaseSecretDisplay
      :default-title="previewI18n.t('web.secrets.you_have_a_message')"
      :domain-branding="domainBranding"
      :preview-i18n="previewI18n"
      :is-revealed="isRevealed"
      :corner-class="cornerClass"
      :font-class="fontFamilyClass"
      :heading-class="headingFontClass">
      <template #content>
        <textarea
          v-if="isRevealed"
          readonly
          :class="[cornerClass]"
          class="w-full resize-none border-0 bg-transparent
              font-mono text-xs text-gray-700
              focus:ring-0 sm:text-base dark:text-gray-300"
          rows="3"
          :aria-label="t('web.secrets.sample_secret_content')"
          :value="textareaPlaceholder"></textarea>

        <div
          v-else
          class="flex items-center text-gray-400 dark:text-gray-500"
          :class="[cornerClass, fontFamilyClass]">
          <OIcon
            collection="mdi"
            name="eye-off"
            class="mr-2 size-5" />
          <span class="text-sm">{{ previewI18n.t('web.secrets.content_hidden') }}</span>
        </div>
      </template>

      <template #action-button>
        <!-- Action Button -->
        <button
          class="w-full py-3 text-base font-medium transition-colors sm:text-lg"
          :class="[cornerClass, fontFamilyClass]"
          :style="actionButtonStyle"
          @click="toggleReveal"
          :aria-expanded="isRevealed"
          aria-controls="secretContent"
          :aria-label="ariaLabelText">
          {{ isRevealed ? previewI18n.t('web.secrets.hide_secret') : previewI18n.t('web.COMMON.click_to_continue') }}
        </button>
      </template>
    </BaseSecretDisplay>
  </div>
</template>

<style scoped>
.line-clamp-6 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

button:hover {
  filter: brightness(110%);
}

textarea {
  resize: none;
}

@media (prefers-reduced-motion: no-preference) {
  .animate-wiggle {
    animation: wiggle 2s ease-in-out infinite;
  }
}

@keyframes wiggle {
  0%,
  100% {
    transform: rotate(-5deg);
  }

  50% {
    transform: rotate(5deg);
  }
}
</style>
