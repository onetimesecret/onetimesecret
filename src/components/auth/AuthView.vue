<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/components/auth/AuthView.vue -->
<script setup lang="ts">
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import OIcon from '@/components/icons/OIcon.vue';
import { Jurisdiction } from '@/schemas/models';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

interface IconConfig {
  collection: string;
  name: string;
}

interface Props {
  heading: string;
  headingId: string;
  title?: string | null;
  titleLogo?: string | null;
  featureIcon?: IconConfig;
  withSubheading?: boolean;
}

// Define props with defaults
const props = withDefaults(defineProps<Props>(), {
  title: null,
  titleLogo: null,
  withSubheading: false,
  featureIcon: () => ({
    collection: 'material-symbols',
    name: 'mail-lock-outline'
  })
});

// Initialize jurisdiction store
const jurisdictionStore = useJurisdictionStore();
const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

// Compute the current jurisdiction or default to unknown
const currentJurisdiction = computed((): Jurisdiction => getCurrentJurisdiction.value || {
  identifier: 'Unknown Jurisdiction',
  display_name: 'Unknown Jurisdiction',
  domain: '',
  icon: {
    collection: 'mdi',
    name: 'help-circle'
  },
  enabled: false
});

// Compute the background icon based on jurisdiction status
const backgroundIcon = computed((): IconConfig => {
  if (jurisdictionStore.enabled && getCurrentJurisdiction.value?.icon) {
    return getCurrentJurisdiction.value.icon;
  }
  return props.featureIcon;
});


// Compute the icon to show based on jurisdiction status

const iconToShow = computed((): IconConfig => {
  if (jurisdictionStore.enabled && getCurrentJurisdiction.value?.icon) {
    return getCurrentJurisdiction.value.icon;
  }
  return props.featureIcon;
});
</script>

<template>
  <div
    class="relative flex min-h-screen items-start justify-center overflow-hidden
              bg-gray-50 px-4
              pt-12
              dark:bg-gray-900
              sm:px-6 sm:pt-16
              lg:px-8">
    <!-- Background Icon -->
    <div
      class="absolute inset-0 overflow-hidden
                opacity-5
                dark:opacity-5">
      <OIcon
        :collection="backgroundIcon.collection"
        :name="backgroundIcon.name"
        size="24"
        class="blur-x absolute left-1/2 top-32 h-auto transform-cpu
                   w-full -translate-x-1/2 translate-y-0 scale-[5]
                   object-cover object-center
                   backdrop-invert"
        aria-hidden="true"
      />
    </div>

    <!-- Page Title -->
    <div class="relative z-10 w-full min-w-[320px] max-w-2xl space-y-4">
      <!-- Title Icon -->
      <div class="flex flex-col items-center">
        <RouterLink to="/">
          <OIcon
            :collection="iconToShow.collection"
            :name="iconToShow.name"
            size="32"
            class="mb-8 size-24 text-brand-600
                      dark:text-brand-400"
            aria-hidden="true"
          />
        </RouterLink>
      </div>

      <!-- Title Text -->
      <div class="text-center">
        <h2
          :id="headingId"
          class="text-2xl font-bold
                   text-gray-900
                   dark:text-white">
          {{ heading }}
        </h2>
        <p
          v-if="withSubheading"
          class="mt-2 flex items-center
            justify-center
            text-lg text-gray-600
            dark:text-gray-400">
          <span
            v-if="jurisdictionStore.enabled"
            class="mr-1">
            Serving you from the <span lang="en">{{ currentJurisdiction.identifier }}</span>
          </span>
        </p>
      </div>

      <!-- Form Card -->
      <div
        class="mt-4 rounded-lg
                  border
                  border-gray-200
                  bg-white
                  p-6
                  shadow-md dark:border-gray-700
                  dark:bg-gray-800">
        <slot name="form"></slot>
      </div>

      <!-- Footer with subtle horizontal rule -->
      <div class="mt-4 text-center">
        <hr class="mx-auto my-4 w-1/4 border-gray-300 dark:border-gray-700" />
        <slot name="footer"></slot>
      </div>
    </div>
  </div>
</template>
