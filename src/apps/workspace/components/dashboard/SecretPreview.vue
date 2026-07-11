<!-- src/apps/workspace/components/dashboard/SecretPreview.vue -->

<script setup lang="ts">
import BaseSecretDisplay from '@/apps/secret/components/branded/BaseSecretDisplay.vue';
import { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useLogoImage } from '@/shared/composables/useLogoImage';
import {
CornerStyle,
FontFamily,
borderRadiusToCss,
cornerStyleClasses,
fontFamilyClasses
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
  onLogoUpload: (file: File) => Promise<void>;
  onLogoRemove: () => Promise<void>;
  secretIdentifier: string;
  previewI18n: Composer;
}>();

// Logo validity + data-URL derivation shared with the Simple form's
// BrandLogoField (useLogoImage), so the two upload entry points can't drift.
const { isValidLogo, logoSrc, onFileChange } = useLogoImage(() => props.logoImage);

const isRevealed = ref(false);
const textareaPlaceholder = computed(() => props.previewI18n.t('web.secrets.sample_secret_content_this_could_be_sensitive_data'));

const ariaLabelText = computed(() =>
  isRevealed.value
    ? props.previewI18n.t('web.secrets.hide_secret_message')
    : props.previewI18n.t('web.secrets.view_secret_message')
)

const handleLogoChange = (event: Event) => onFileChange(event, props.onLogoUpload);

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

const fontFamilyClass = computed(() => {
  const font = props.domainBranding?.font_family as FontFamily | undefined;
  return fontFamilyClasses[font ?? FontFamily.SANS];
});

// Mirror identityStore.headingFontClass: heading_font falls back to the body
// font_family, so the preview heading tracks the recipient page.
const headingFontClass = computed(() => {
  const heading = (props.domainBranding?.heading_font ??
    props.domainBranding?.font_family) as FontFamily | undefined;
  return fontFamilyClasses[heading ?? FontFamily.SANS];
});

// Expanded vocabulary (#3646). The preview renders an arbitrary domain's
// settings (not the editing admin's injected palette). Scope this domain's
// border_radius to a local --radius-brand so every `rounded-brand` descendant
// (logo, content box, textarea, button, and BaseSecretDisplay's content
// wrapper) resolves to THIS domain's radius — matching the recipient page.
// Applied via :style fallthrough on <BaseSecretDisplay>; depends on it staying
// single-root (fallthrough merges onto that one root element).
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
  <!-- Updated -->
  <BaseSecretDisplay
    :style="rootStyle"
    :default-title="previewI18n.t('web.secrets.you_have_a_message')"
    :domain-branding="domainBranding"
    :preview-i18n="previewI18n"
    :is-revealed="isRevealed"
    :corner-class="cornerClass"
    :font-class="fontFamilyClass"
    :heading-class="headingFontClass">
    <!-- Logo Upload Area -->
    <template #logo>
      <div class="group relative mx-auto sm:mx-0">
        <label
          class="block cursor-pointer"
          for="logo-upload"
          role="button">
          <div
            :class="[cornerClass, {
              'animate-wiggle': !isValidLogo
            }]"
            class="hover:ring-primary-500 flex size-14 items-center justify-center overflow-hidden bg-gray-100 hover:ring-2 hover:ring-offset-2 sm:size-16 dark:bg-gray-700">
            <img
              v-if="isValidLogo"
              :src="logoSrc"
              :alt="logoImage?.filename || t('web.layout.brand_logo')"
              class="size-16 object-contain"
              :class="{
                [cornerClass]: true,
              }" />
            <svg
              v-else
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
        </label>

        <!-- Help text -->
        <div
          id="logoHelp"
          class="sr-only">
          {{ t('web.branding.click_to_upload_a_logo_with_recommendation') }}
        </div>

        <input
          id="logo-upload"
          type="file"
          class="hidden"
          accept="image/*"
          @change="handleLogoChange"
          aria-labelledby="logoHelp" />

        <!-- Hover/Focus Controls -->
        <div
          v-if="isValidLogo"
          class="absolute inset-0 flex items-center justify-center rounded-lg bg-black/70 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100"
          role="group"
          :aria-label="t('web.branding.logo_controls')">
          <button
            @click.stop="onLogoRemove"
            class="rounded-md bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700 focus:bg-red-700 focus:ring-2 focus:ring-red-500 focus:ring-offset-2 focus:outline-none">
            <span class="flex items-center gap-1">
              <OIcon
                collection="mdi"
                name="trash-can"
                class="size-4" />
              {{ t('web.COMMON.remove') }}
            </span>
          </button>
        </div>
      </div>
    </template>

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
