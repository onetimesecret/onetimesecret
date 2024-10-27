<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/components/auth/AuthView.vue -->
<template>
  <div class="relative flex min-h-screen items-start justify-center overflow-hidden
              px-4 pt-12
              bg-gray-50
              dark:bg-gray-900
              sm:px-6 sm:pt-16
              lg:px-8">

    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden
                opacity-5
                dark:opacity-10">
      <Icon :icon="backgroundIcon"
            class="absolute top-0 left-1/2 h-auto w-full
                   transform -translate-x-1/2 translate-y-0 scale-150
                   object-cover object-center
                   blur-x backdrop-invert"
            aria-hidden="true" />
    </div>

    <!-- Page Title -->
    <div class="relative z-10 w-full max-w-2xl space-y-4 min-w-[320px]">

      <!-- Title Icon -->
      <div class="flex flex-col items-center">
        <Icon :icon="iconToShow"
              class="mb-8 h-24 w-24
                     text-brand-600
                     dark:text-brand-400"
              aria-hidden="true" />
      </div>

      <!-- Title Text -->
      <div class="text-center">
        <h2 :id="headingId"
            class="text-2xl font-bold
                   text-gray-900
                   dark:text-white">
          {{ heading }}
        </h2>
        <p v-if="withSubheading"
            class="flex items-center justify-center
            mt-2
            text-lg text-gray-600
            dark:text-gray-400">
          <span v-if="jurisdictionStore.enabled"
                class="mr-1">
            Serving you from the <span lang="en">{{ currentJurisdiction.identifier }}</span>
          </span>
        </p>
      </div>

      <!-- Form Card -->
      <div class="mt-4 p-6
                  rounded-lg
                  shadow-md
                  bg-white
                  dark:bg-gray-800
                  border border-gray-200
                  dark:border-gray-700">
        <slot name="form"></slot>
      </div>

      <!-- Footer with subtle horizontal rule -->
      <div class="mt-4 text-center">
        <hr class="my-4 border-gray-300 dark:border-gray-700 mx-auto w-1/4">
        <slot name="footer"></slot>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { Icon } from '@iconify/vue';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { storeToRefs } from 'pinia';

// Define props for the component
const props = withDefaults(defineProps<{
  heading: string;
  headingId: string;
  title?: string | null;
  titleLogo?: string | null;
  featureIcon?: string;
  withSubheading?: string | null;
}>(), {
  title: null,
  titleLogo: null,
  featureIcon: 'ic:outline-mail-lock',
});

// Initialize jurisdiction store
const jurisdictionStore = useJurisdictionStore();
const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

// Compute the current jurisdiction or default to unknown
const currentJurisdiction = computed(() => getCurrentJurisdiction.value || {
  identifier: 'Unknown Jurisdiction',
  display_name: 'Unknown Jurisdiction',
  domain: '',
  icon: 'mdi:help-circle',
});

// Compute the background icon based on jurisdiction status
const backgroundIcon = computed(() => jurisdictionStore.enabled ? currentJurisdiction.value.icon : props.featureIcon);

// Compute the icon to show based on jurisdiction status
const iconToShow = computed(() => jurisdictionStore.enabled ? currentJurisdiction.value.icon : props.featureIcon);
</script>
