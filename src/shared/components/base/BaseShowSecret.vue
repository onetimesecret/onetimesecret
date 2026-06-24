<!-- src/shared/components/base/BaseShowSecret.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  /**
   * Base component for secret display implementations
   * Provides core secret loading/display logic and structural slots for customization
   *
   * @slot header - Page header content (logos, titles, etc)
   * @slot loading - Loading indicator while fetching secret
   * @slot error - Error display when something goes wrong
   * @slot alerts - Warning/notification alerts for secret owners (includes uiConfig)
   * @slot confirmation - Secret confirmation form and related content
   * @slot reveal - Secret display content when revealed
   * @slot onboarding - Additional content shown during confirmation (e.g., marketing)
   * @slot unknown - Content shown when secret is not found
   * @slot footer - Page footer content
   */

  import SecretSkeleton from '@/shared/components/closet/SecretSkeleton.vue';
  import { useSecret } from '@/shared/composables/useSecret';
  import { useSecretContext } from '@/shared/composables/useSecretContext';
  import { computed, onMounted } from 'vue';
  import { onBeforeRouteUpdate } from 'vue-router';

  const { t } = useI18n();

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

  // #3424: distinguish a terminal "not found" (404 — consumed/expired/missing),
  // which legitimately renders the "viewed or expired" UnknownSecret view, from a
  // load/parse/network failure, which must NOT masquerade as it. The latter shows
  // the (previously dead) `error` slot with neutral, retryable copy.
  const isNotFound = computed(() => state.errorCode === 404 || state.errorCode === '404');
  const showLoadError = computed(
    () => !state.isLoading && !record.value && !!state.error && !isNotFound.value
  );

  // Actor-based UI configuration derived from auth state and ownership
  const { uiConfig, actorRole } = useSecretContext({
    isOwner: () => details.value?.is_owner ?? false,
  });

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
    :aria-label="t('web.secrets.secret_viewing_page')">
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
        class="animate-pulse motion-reduce:animate-none space-y-6 p-4">
        <SecretSkeleton />
      </div>

      <!-- Initial Loading - Prevent UnknownSecret flash -->
      <div
        v-else-if="!state.isLoading && !record && !state.error"
        class="animate-pulse motion-reduce:animate-none space-y-6 p-4">
        <SecretSkeleton />
      </div>

      <!-- Load / parse / network error — kept DISTINCT from the terminal
           "viewed or expired" view so a transient or schema failure isn't
           reported to the recipient as a consumed secret (#3424). -->
      <template v-else-if="showLoadError">
        <slot
          name="error"
          :error="state.error"
          :retry="load">
          <div
            role="alert"
            class="rounded-lg border-l-4 border-red-500 bg-red-50 p-4 text-red-700
              dark:bg-red-900/20 dark:text-red-200">
            {{ state.error || t('web.COMMON.unexpected_error') }}
          </div>
        </slot>
      </template>

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
          :show-secret="details.show_secret"
          :ui-config="uiConfig"
          :actor-role="actorRole"></slot>

        <template v-if="!details.show_secret">
          <!-- Confirmation form slot -->
          <slot
            name="confirmation"
            :secret-identifier="secretIdentifier"
            :record="record"
            :details="details"
            :error="state.error"
            :is-loading="state.isLoading"
            :on-confirm="handleUserConfirmed"></slot>

          <!-- Optional onboarding/marketing slot -->
          <slot
            name="onboarding"
            :record="record"
            :details="details"
            :ui-config="uiConfig"></slot>
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
      <div class="mx-auto w-full max-w-4xl px-4">
        <slot
          name="footer"
          :record="record"
          :details="details"
          :site-host="props.siteHost"></slot>
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
