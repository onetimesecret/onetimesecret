<!-- src/components/base/BaseShowSecret.vue -->

<script setup lang="ts">  import SecretSkeleton from '@/components/closet/SecretSkeleton.vue';
  import { useSecret } from '@/composables/useSecret';
  import { onMounted } from 'vue';
  import { onBeforeRouteUpdate } from 'vue-router';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

  /**
   * Base component for secret display implementations
   * Provides core secret loading/display logic and structural slots for customization
   *
   * @slot header - Page header content (logos, titles, etc)
   * @slot loading - Loading indicator while fetching secret
   * @slot error - Error display when something goes wrong
   * @slot alerts - Warning/notification alerts for secret owners
   * @slot confirmation - Secret confirmation form and related content
   * @slot reveal - Secret display content when revealed
   * @slot onboarding - Additional content shown during confirmation (e.g., marketing)
   * @slot unknown - Content shown when secret is not found
   * @slot footer - Page footer content
   */

  export interface Props {
    secretIdentifier: string;
    siteHost: string;
    domainStrategy?: string;
    displayDomain?: string;
    domainId?: string | null;
    branded?: boolean;
  }

  const props = defineProps<Props>();

  const { record, details, state, load, reveal } = useSecret(props.secretIdentifier);

  const handleUserConfirmed = (passphrase: string) => {
    reveal(passphrase);
  };

  onBeforeRouteUpdate((to, from, next) => {
    load();
    next();
  });

  onMounted(() => {
    load();
  });
</script>

<template>
  <main
    class="grid min-h-screen grid-rows-[auto_minmax(0,max-content)_auto] gap-4"
    role="main"
    :aria-label="t('secret-viewing-page')">
    <header
      v-if="$slots.header"
      class="w-full bg-white dark:bg-gray-900">
      <div class="mx-auto w-full max-w-4xl px-4">
        <slot
          name="header"
          :record="record"
          :details="details"></slot>
      </div>
    </header>

    <!-- Content wrapper  -->
    <div class="mx-auto w-full max-w-4xl px-4">
      <!-- Global Loading State -->
      <div
        v-if="state.isLoading"
        class="animate-pulse space-y-6 p-4">
        <SecretSkeleton />
      </div>

      <!-- Initial Loading - Prevent UnknownSecret flash -->
      <div
        v-else-if="!state.isLoading && !record && !state.error"
        class="animate-pulse space-y-6 p-4">
        <SecretSkeleton />
      </div>

      <!-- Unknown Secret State -->
      <template v-else-if="!record">
        <slot
          name="unknown"
          :branded="branded"
          :details="details">
        </slot>
      </template>

<style scoped>
  /* Common base styles */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
