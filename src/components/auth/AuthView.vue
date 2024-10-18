<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/components/auth/AuthLayout.vue -->
<template>
  <div class="relative flex min-h-screen items-start justify-center overflow-hidden px-4 sm:px-6 lg:px-8
              bg-gray-50 dark:bg-gray-900 pt-16 sm:pt-24">
    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden opacity-5 dark:opacity-10">
      <Icon :icon="backgroundIcon"
            class="absolute top-0 left-1/2 h-auto w-full transform -translate-x-1/2 translate-y-0 scale-150
                   object-cover object-center blur-x backdrop-invert"
            aria-hidden="true" />
    </div>

    <div class="relative z-10 w-full max-w-md space-y-6">
      <div class="flex flex-col items-center">
        <Icon :icon="iconToShow"
              class="mb-24 h-40 w-40 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
      </div>
      <div class="text-center">
        <h2 :id="headingId"
            class="text-3xl font-extrabold text-gray-900 dark:text-white">
          {{ heading }}
        </h2>
        <p class="mt-2 text-base text-gray-600 dark:text-gray-400 flex items-center justify-center">
          <span v-if="jurisdictionStore.enabled" class="mr-1">
            Serving you from <span lang="en">{{ currentJurisdiction.identifier }}</span>
          </span>
        </p>
      </div>

      <div class="mt-6 rounded-lg p-8 shadow-xl bg-white dark:bg-gray-800">
        <slot name="form"></slot>
      </div>

      <div class="mt-4 text-center">
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

defineProps<{
  heading: string;
  headingId: string;
}>();

const jurisdictionStore = useJurisdictionStore();
const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

const featureIcon = 'ic:outline-mail-lock';

const currentJurisdiction = computed(() => getCurrentJurisdiction.value || {
  identifier: 'Unknown Jurisdiction',
  display_name: 'Unknown Jurisdiction',
  domain: '',
  icon: 'mdi:help-circle',
});

const backgroundIcon = computed(() => jurisdictionStore.enabled ? currentJurisdiction.value.icon : featureIcon);
const iconToShow = computed(() => jurisdictionStore.enabled ? currentJurisdiction.value.icon : featureIcon);
</script>
