<!-- src/shared/components/layout/TransactionalHeader.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import MastHead from '@/shared/components/layout/MastHead.vue';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';

  const { t } = useI18n();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const { authentication } = storeToRefs(bootstrapStore);

  const isUserPresent = computed(() => authStore.isUserPresent);

  // Show minimal nav when MastHead is hidden but navigation is enabled.
  // This handles custom domain pages where the logo lives in page content
  // but Sign In still needs a layout-level home.
  const showMinimalNav = computed(
    () => !props.displayMasthead && props.displayNavigation && !isUserPresent.value
  );
</script>

<template>
  <header class="bg-white dark:bg-gray-900">
    <div class="container mx-auto min-w-[320px] max-w-2xl p-4">
      <MastHead v-if="displayMasthead" v-bind="props" />

      <!-- Minimal nav for custom domain pages without MastHead.
           max-w-xl aligns with BrandedHomepage content column. -->
      <nav
        v-else-if="showMinimalNav"
        role="navigation"
        :aria-label="t('web.layout.main_navigation')"
        class="mx-auto flex w-full max-w-xl justify-end font-brand text-sm sm:text-base">
        <template v-if="authentication?.enabled">
          <router-link
            v-if="authentication?.signin"
            to="/signin"
            :title="t('web.homepage.log_in_to_onetime_secret')"
            data-testid="header-signin-link"
            class="text-gray-600 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ t('web.COMMON.header_sign_in') }}
          </router-link>
        </template>
      </nav>
    </div>
  </header>
</template>
