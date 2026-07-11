<!-- src/shared/components/base/BaseUnknownSecret.vue -->

<script setup lang="ts">
  import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';
  import {
    cornerStyleClasses,
    fontFamilyClasses,
    type FontFamily,
  } from '@/shared/utils/brand-helpers';
  import { computed } from 'vue';

  export interface Props {
    branded?: boolean;
    brandSettings?: BrandSettings;
  }

  const props = defineProps<Props>();

  /**
   * Root corner-radius class. Mirrors identityStore's cornerClass derivation
   * (#3646: `border_radius` supersedes the legacy 3-value `corner_style` →
   * `rounded-brand`), but reads from props because this base is props-only and
   * cannot touch the store. Unbranded/unset falls back to `rounded-lg`, the
   * canonical unknown-card default (matches store DEFAULT_CORNER_CLASS). Applied
   * as the SOLE border-radius utility on the root so nothing fights it.
   */
  const cornerClass = computed(() => {
    if (!props.branded) return 'rounded-lg';
    const bs = props.brandSettings;
    if (bs?.border_radius != null && bs.border_radius !== '') return 'rounded-brand';
    return bs?.corner_style ? cornerStyleClasses[bs.corner_style] ?? 'rounded-lg' : 'rounded-lg';
  });

  /**
   * Computes background color with 15% opacity for branded icon container
   */
  const getBackgroundColor = (color?: string): string => color ? `${color}15` : '';
</script>

<template>
  <div
    class="bg-white p-8 dark:bg-gray-800"
    :class="[
      cornerClass,
      branded ? 'w-full shadow-xl' : 'shadow-md',
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
