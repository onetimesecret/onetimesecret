<!-- src/apps/session/components/AuthView.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { Jurisdiction } from '@/schemas/models';
  import { useJurisdictionStore } from '@/shared/stores/jurisdictionStore';
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
    withHeading?: boolean;
    withSubheading?: boolean;
    hideIcon?: boolean;
    hideBackgroundIcon?: boolean;
  }

  // Define props with defaults
  const props = withDefaults(defineProps<Props>(), {
    title: null,
    titleLogo: null,
    withHeading: true,
    withSubheading: false,
    hideIcon: false,
    hideBackgroundIcon: false,
    featureIcon: () => ({
      collection: 'material-symbols',
      name: 'mail-lock-outline',
    }),
  });

  const { t } = useI18n();

  // Initialize jurisdiction store
  const jurisdictionStore = useJurisdictionStore();
  const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

  // Compute the current jurisdiction or default to unknown
  const currentJurisdiction = computed(
    (): Jurisdiction =>
      getCurrentJurisdiction.value || {
        identifier: t('unknown-jurisdiction'),
        display_name: t('unknown-jurisdiction'),
        domain: '',
        icon: {
          collection: 'mdi',
          name: 'help-circle',
        },
        enabled: false,
      }
  );

  // Compute the background icon based on jurisdiction status
  const backgroundIcon = computed((): IconConfig => {
    if (jurisdictionStore.enabled && getCurrentJurisdiction.value?.icon) {
      return getCurrentJurisdiction.value.icon;
    }
    return props.featureIcon || {
      collection: 'material-symbols',
      name: 'mail-lock-outline',
    };
  });

  // Compute the icon to show based on jurisdiction status

  const iconToShow = computed((): IconConfig => {
    if (jurisdictionStore.enabled && getCurrentJurisdiction.value?.icon) {
      return getCurrentJurisdiction.value.icon;
    }
    return props.featureIcon || {
      collection: 'material-symbols',
      name: 'mail-lock-outline',
    };
  });
</script>

<template>
  <div
    class="relative flex min-h-screen items-start justify-center overflow-hidden bg-gray-50 px-4 pt-12 dark:bg-gray-900 sm:px-6 sm:pt-16 lg:px-8">
    <!-- Background Icon -->
    <div v-if="!hideBackgroundIcon" class="fixed inset-0 overflow-hidden opacity-5 dark:opacity-5 blur-md">
      <OIcon
        v-if="backgroundIcon && backgroundIcon.collection && backgroundIcon.name"
        :collection="backgroundIcon.collection"
        :name="backgroundIcon.name"
        class="absolute left-1/2 top-0 h-auto w-full -translate-x-1/2 translate-y-[120%] scale-[9] transform-cpu object-cover object-center backdrop-invert"
        aria-hidden="true" />
    </div>

    <!-- Page Title -->
    <div class="relative z-10 w-full min-w-[320px] max-w-md space-y-12">
      <!-- Title Icon -->
      <div class="flex flex-col items-center" :class="{ 'invisible': hideIcon }">
        <RouterLink to="/" class="group">
          <div class="relative">
            <!-- Subtle glow effect -->
            <div class="absolute inset-0 rounded-full bg-brand-500/10 blur-xl transition-all duration-300 group-hover:bg-brand-500/20 dark:bg-brand-400/10 dark:group-hover:bg-brand-400/20"></div>
            <!-- Icon -->
            <OIcon
              v-if="iconToShow && iconToShow.collection && iconToShow.name"
              :collection="iconToShow.collection"
              :name="iconToShow.name"
              size="32"
              class="relative size-24 transition-transform duration-300 group-hover:scale-105 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </div>
        </RouterLink>
      </div>

      <!-- Title Text -->
      <div class="space-y-3 text-center">
        <h2
          :id="headingId"
          v-if="withHeading"
          class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ heading }}
        </h2>
        <p
          v-if="withSubheading"
          class="flex items-center justify-center text-sm text-gray-600 dark:text-gray-400">
          <span
            v-if="jurisdictionStore.enabled"
            class="mr-1">
            {{ t('serving-you-from-the') }}:
            <span class="font-medium text-gray-700 dark:text-gray-300">{{ currentJurisdiction.display_name }}</span>
          </span>
        </p>
      </div>

      <!-- Form Card -->
      <div
        role="region"
        :aria-labelledby="headingId"
        class="rounded-lg border border-gray-200 bg-white p-6 shadow-md dark:border-gray-700 dark:bg-gray-800">
        <slot name="form"></slot>
      </div>

      <!-- Footer -->
      <div class="space-y-6 text-center">
        <div class="text-sm">
          <slot name="footer"></slot>
        </div>

        <!-- Subtle home link for escape route -->
        <div class="border-t border-gray-200 pt-6 dark:border-gray-700">
          <RouterLink
            to="/"
            class="inline-flex items-center text-sm text-gray-500 transition-colors duration-200 hover:text-gray-700 dark:text-gray-500 dark:hover:text-gray-400"
            :aria-label="t('return-to-home-page')">
            <span>{{ t('return-home') }}</span>
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
