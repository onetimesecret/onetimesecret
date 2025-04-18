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

  import SecretSkeleton from '@/components/closet/SecretSkeleton.vue';
  import { useSecret } from '@/composables/useSecret';
  import { onMounted, Ref } from 'vue';
  import { onBeforeRouteUpdate } from 'vue-router';

  export interface Props {
    secretKey: string;
    siteHost: string;
    domainStrategy?: string;
    displayDomain?: string;
    domainId?: string | null;
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
    class="min-h-screen grid grid-rows-[auto_minmax(0,max-content)_auto] gap-4"
    role="main"
    :aria-label="$t('secret-viewing-page')">
    <header
      v-if="$slots.header"
      class="w-full bg-white dark:bg-gray-900">
      <div class="w-full max-w-4xl mx-auto px-4">
        <slot
          name="header"
          :record="record"
          :details="details"></slot>
      </div>
    </header>

    <!-- Content wrapper  -->
    <div class="w-full max-w-4xl mx-auto px-4">
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
    </div>

    <!-- Footer wrapper -->
    <footer
      v-if="$slots.footer"
      class="w-full bg-white dark:bg-gray-900">
      <div class="w-full max-w-4xl mx-auto px-4">
        <slot
          name="footer"
          :record="record"
          :details="details"
          :siteHost="props.siteHost"></slot>
      </div>
    </footer>
  </main>
</template>

<style scoped>
  /* Common base styles */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
