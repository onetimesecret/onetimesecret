<!-- src/apps/secret/reveal/branded/UnknownSecret.vue -->

<script setup lang="ts">
  import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';
  import BaseUnknownSecret from '@/shared/components/base/BaseUnknownSecret.vue';
  import {
    resolveBodyFontClass,
    resolveHeadingFontClass,
  } from '@/shared/utils/brand-helpers';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

const { t } = useI18n();

  interface Props {
    brandSettings?: BrandSettings;
    branded?: boolean;
  }

  const props = defineProps<Props>();

  const fontClass = computed(() => resolveBodyFontClass(props.brandSettings));

  const headingClass = computed(() => resolveHeadingFontClass(props.brandSettings));
</script>

<template>
  <BaseUnknownSecret
    :branded="true"
    :brand-settings="brandSettings">
    <!-- Header with icon and title -->
    <template #header>
      <div class="mb-8 flex items-center space-x-4">
        <div
          class="flex size-12 items-center justify-center rounded-full bg-brand-500/10">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-6"
            :class="
              brandSettings?.button_text_light
                ? 'text-white'
                : 'text-brand-600 dark:text-brand-400'
            "
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
        </div>
        <div>
          <h2
            class="text-xl font-semibold text-gray-900 dark:text-white"
            :class="headingClass">
            {{ t('web.COMMON.not_found') }}
          </h2>
        </div>
      </div>
    </template>

    <!-- Main message -->
    <template #message="{ }">
      <p
        class="text-gray-600 dark:text-gray-300"
        :class="fontClass">
        <span v-if="brandSettings?.instructions_post_reveal">
          {{ brandSettings?.instructions_post_reveal }}
        </span>
        <span v-else>
          {{ t('web.homepage.information_shared_through_this_service_can_only') }}
        </span>
      </p>
    </template>

    <!-- Action button -->
    <template #action="{ }">
      <!-- prettier-ignore-attribute class -->
      <router-link
        to="/"
        class="inline-block rounded-lg border-2 border-transparent
          bg-brand-500 px-4 py-2 transition duration-300 ease-in-out
          hover:bg-brand-600 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none
          dark:focus:ring-brand-400 dark:focus:ring-offset-gray-900"
        :class="[
          fontClass,
          (brandSettings?.button_text_light ?? true) ? 'text-white' : 'text-gray-900',
        ]">
        {{ t('web.layout.return_to_home') }}
      </router-link>
    </template>
  </BaseUnknownSecret>
</template>
