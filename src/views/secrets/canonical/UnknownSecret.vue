<template>
  <div
    :class="[
      'bg-white dark:bg-gray-800',
      branded ? 'shadow-xl' : 'shadow-md',
      branded ? 'w-full' : '',
      'rounded-lg p-8',
      branded && brandSettings?.corner_style === 'sharp' ? 'rounded-none' : ''
    ]"
    :style="branded && brandSettings ? {
      fontFamily: brandSettings.font_family || 'inherit'
    } : {}">
    <!-- Icon Section -->
    <div
      :class="[
        branded ? 'mb-8 flex items-center space-x-4' : 'mb-8 text-center'
      ]">
      <template v-if="branded">
        <div
          class="flex size-12 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900"
          :style="brandSettings?.primary_color ? {
            backgroundColor: `${brandSettings.primary_color}15`,
          } : {}">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-6"
            :class="brandSettings?.button_text_light ? 'text-white' : 'text-brand-600 dark:text-brand-400'"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
            />
          </svg>
        </div>
        <div>
          <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
            No Longer Available
          </h2>
        </div>
      </template>
      <template v-else>
        <svg
          class="mx-auto mb-4 size-20 text-brand-500"
          width="60"
          height="60"
          viewBox="0 0 24 24"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          aria-hidden="true">
          <path
            d="M10 14L12 12M12 12L14 10M12 12L10 10M12 12L14 14M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>

        <h1
          class="mb-6 text-3xl font-bold text-gray-800 dark:text-white"
          aria-label="Information no longer available">
          That information is no longer available.
        </h1>
      </template>
    </div>

    <!-- Content Section -->
    <div :class="{ 'space-y-6': branded }">
      <p
        :class="[
          'text-gray-600 dark:text-gray-300',
          branded ? '' : 'mb-8 text-lg'
        ]">
        <template v-if="branded && brandSettings?.instructions_post_reveal">
          {{ brandSettings.instructions_post_reveal }}
        </template>
        <template v-else>
          <em>Welcome to Onetime Secret.</em>
          Information shared through our service can only be accessed once. Once viewed, the
          content is permanently deleted from our servers to ensure confidentiality.
          <span v-if="!branded">This approach helps protect your sensitive data by limiting its exposure and preventing unauthorized access.</span>
        </template>
      </p>

      <div
        :class="[
          'border-l-4 border-brandcomp-500 bg-brandcomp-50 dark:bg-brandcomp-900',
          branded ? 'p-4' : 'mb-8 p-5'
        ]">
        <p
          :class="[
            'text-brandcomp-700 dark:text-brandcomp-200',
            !branded && 'text-lg font-medium'
          ]">
          If you're unsure what to do next, please follow up with the person who sent you this link
          for more information.
        </p>
      </div>

      <router-link
        to="/"
        :class="[
          'inline-block rounded-lg border-2 transition duration-300 ease-in-out',
          'bg-white dark:bg-gray-800',
          'hover:bg-brand-100 dark:hover:bg-gray-700',
          'focus:outline-none focus:ring-2 focus:ring-offset-2 dark:focus:ring-offset-gray-900',
          'focus:ring-brand-500 dark:focus:ring-brand-400',
          branded ? 'px-4 py-2' : 'px-6 py-3 font-brand text-lg hover:border-brand-600 dark:hover:border-brand-400'
        ]"
        :style="branded && brandSettings?.primary_color ? {
          color: brandSettings.primary_color,
          borderColor: brandSettings.primary_color
        } : {
          color: 'var(--color-brand-500)',
          borderColor: 'var(--color-brand-500)'
        }"
        :aria-label="branded ? undefined : 'Return to home page'">
        Return to Home
      </router-link>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { BrandSettings } from '@/schemas/models/domain/brand';

interface Props {
  branded?: boolean;
  brandSettings?: BrandSettings;
}

defineProps<Props>();
</script>
