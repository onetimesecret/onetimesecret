<!-- src/components/secrets/branded/SecretConfirmationForm.vue -->

<script setup lang="ts">
  import { Secret, SecretDetails, brandSettingschema } from '@/schemas/models';
  import {
    CornerStyle,
    FontFamily,
    cornerStyleClasses,
    fontFamilyClasses,
  } from '@/schemas/models/domain/brand';
  import { useProductIdentity } from '@/stores/identityStore';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import BaseSecretDisplay from './BaseSecretDisplay.vue';


const { t } = useI18n();
  interface Props {
    secretIdentifier: string;
    record: Secret | null;
    details: SecretDetails | null;
    domainId: string;
    isSubmitting: boolean;
    error: unknown;
  }

  const props = defineProps<Props>();

  const i18n = useI18n();
  const { t } = i18n;

  const emit = defineEmits(['user-confirmed']);
  // const useSecret = useSecret();
  const passphrase = ref('');

  const submitForm = async () => {
    emit('user-confirmed', passphrase.value);
  };

  const productIdentity = useProductIdentity();
  const brandSettings = productIdentity.brand; // Not reactive
  const defaultBranding = brandSettingschema.parse({});
  const safeBrandSettings = computed(() =>
    brandSettings ? brandSettingschema.parse(brandSettings) : defaultBranding
  );

  const cornerClass = computed(() => {
    const style = safeBrandSettings.value?.corner_style as CornerStyle | undefined;
    return cornerStyleClasses[style ?? CornerStyle.ROUNDED];
  });

  const fontFamilyClass = computed(() => {
    const font = safeBrandSettings.value?.font_family as FontFamily | undefined;
    return fontFamilyClasses[font ?? FontFamily.SANS];
  });

  const hasImageError = ref(false);

  const cornerStyle = computed(() => {
    switch (brandSettings?.corner_style) {
      case 'rounded':
        return 'rounded-lg';
      case 'pill':
        return 'rounded-full';
      case 'square':
        return 'rounded-none';
      default:
        return 'rounded-lg';
    }
  });

  const handleImageError = () => {
    hasImageError.value = true;
  };

  const buttonText = computed(() => props.isSubmitting ? t('web.COMMON.submitting') : t('click-to-continue'));
  // Prepare the standardized path to the logo image.
  // Note that the file extension needs to be present but is otherwise not used.
  const logoImage = ref<string>(`/imagine/${props.domainId}/logo.png`);
</script>

<template>
  <BaseSecretDisplay
    :default-title="t('you-have-a-message')"
    :preview-i18n="i18n"
    :domain-branding="safeBrandSettings"
    :corner-class="cornerClass"
    :font-class="fontFamilyClass"
    :instructions="brandSettings?.instructions_pre_reveal">
    <template #logo>
      <div class="relative mx-auto sm:mx-0">
        <div :class="[cornerStyle, 'size-14 overflow-hidden sm:size-16']">
          <!-- Background container with matching corner style -->
          <div
            :class="[
              cornerStyle,
              'absolute inset-0 flex items-center justify-center bg-gray-100 dark:bg-gray-700',
              { hidden: logoImage && !hasImageError },
            ]">
            <!-- Default lock icon -->
            <svg
              v-if="!logoImage || hasImageError"
              class="size-8 text-gray-400 dark:text-gray-500"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>

          <!-- Logo -->
          <img
            v-if="logoImage && !hasImageError"
            :src="logoImage"
            alt="t('brand-logo')"
            class="size-full object-contain"
            :class="cornerStyle"
            @error="handleImageError" />
        </div>
      </div>
    </template>

<style>
  .line-clamp-6 {
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-clamp: 3;
  }

  /* Ensure focus outline is visible in all color schemes */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
