<!-- BaseShowSecret.vue -->
<script setup lang="ts">
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

  import { useSecret } from '@/composables/useSecret';
  import { onMounted, Ref } from 'vue';
  import { onBeforeRouteUpdate } from 'vue-router';

  export interface Props {
    secretKey: string;
    domainStrategy?: string;
    displayDomain?: string;
    domainId?: string | null;
    siteHost?: string;
    branded?: boolean;
  }

  const props = defineProps<Props>();

  const { record, details, state, load, reveal } = useSecret(props.secretKey);

  const handleUserConfirmed = (passphrase: Ref<string>) => {
    reveal(passphrase.value);
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
    class="min-h-screen"
    role="main"
    aria-label="Secret viewing page">
    <div class="w-full max-w-4xl mx-auto">
      <!-- Header slot for branding/title -->
      <slot
        name="header"
        :record="record"
        :details="details"></slot>

      <!-- Global Loading State -->
      <div
        v-if="state.isLoading"
        class="animate-pulse space-y-6 p-4">
        <!-- Header/Title Placeholder -->
        <div class="h-8 w-1/3 rounded-lg bg-gray-200 dark:bg-gray-700"></div>

        <!-- Main Content Box -->
        <div class="rounded-lg border border-gray-200 p-6 dark:border-gray-700">
          <!-- Secret Info Line -->
          <div class="mb-4 h-6 w-2/3 rounded-lg bg-gray-200 dark:bg-gray-700"></div>

          <!-- Form/Content Area -->
          <div class="space-y-4">
            <div class="h-12 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
            <div class="h-12 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
          </div>
        </div>
      </div>

      <!-- Unknown Secret State -->
      <template v-else-if="!record">
        <slot
          name="unknown"
          :branded="branded"
          :details="details">
        </slot>
      </template>

      <!-- Error State -->
      <template v-else-if="state.error">
        <slot
          name="error"
          :error="state.error"
          :branded="branded"></slot>
      </template>

      <!-- Main Content - Valid Secret -->
      <div v-else-if="record && details">
        <!-- Alerts slot for owner warnings -->
        <slot
          name="alerts"
          :record="record"
          :details="details"
          :is-owner="details.is_owner"
          :show-secret="details.show_secret"></slot>

        <template v-if="!details.show_secret">
          <!-- Confirmation form slot -->
          <slot
            name="confirmation"
            :secret-key="secretKey"
            :record="record"
            :details="details"
            :error="state.error"
            :is-loading="state.isLoading"
            :on-confirm="handleUserConfirmed"></slot>

          <!-- Optional onboarding/marketing slot -->
          <slot
            name="onboarding"
            :record="record"
            :details="details"></slot>
        </template>

        <template v-else>
          <!-- Reveal content slot -->
          <slot
            name="reveal"
            :record="record"
            :details="details"></slot>
        </template>
      </div>

      <!-- Footer slot -->
      <slot
        name="footer"
        :record="record"
        :details="details"></slot>
    </div>
  </main>
</template>

<style scoped>
  /* Common base styles */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
