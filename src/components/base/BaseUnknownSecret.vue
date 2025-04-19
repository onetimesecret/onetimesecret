<!-- src/components/base/BaseUnknownSecret.vue -->

<script setup lang="ts">
  import type { BrandSettings } from '@/schemas/models/domain/brand';
  import { fontFamilyClasses, FontFamily } from '@/schemas/models/domain/brand';

  export interface Props {
    branded?: boolean;
    brandSettings?: BrandSettings;
  }

  defineProps<Props>();

  /**
   * Computes background color with 15% opacity for branded icon container
   */
  const getBackgroundColor = (color?: string): string => {
    return color ? `${color}15` : '';
  };
</script>

<template>
  <div
    class="rounded-lg bg-white p-8 dark:bg-gray-800"
    :class="[
      branded ? 'w-full shadow-xl' : 'shadow-md',
      branded && brandSettings?.corner_style === 'sharp' ? 'rounded-none' : '',
      branded && brandSettings?.font_family ? fontFamilyClasses[brandSettings.font_family as FontFamily] : ''
    ]">
    <!-- Header slot for icon and title -->
    <slot
      name="header"
      :branded="branded"
      :brand-settings="brandSettings"
      :get-background-color="getBackgroundColor">
    </slot>

    <!-- Main content slot -->
    <div :class="{ 'space-y-6': branded }">
      <slot
        name="message"
        :branded="branded"
        :brand-settings="brandSettings">
      </slot>

      <slot
        name="alert"
        :branded="branded">
      </slot>

      <!-- Action button slot -->
      <slot
        name="action"
        :branded="branded"
        :brand-settings="brandSettings">
      </slot>
    </div>
  </div>
</template>
