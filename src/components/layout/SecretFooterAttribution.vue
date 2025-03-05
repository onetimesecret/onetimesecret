<!-- src/components/layout/SecretFooterAttribution.vue -->

<script setup lang="ts">
  defineProps<{
    siteHost: string;
    showNav?: boolean;
    showTerms?: boolean;
  }>();
</script>

<template>
  <footer
    class="text-center text-xs text-gray-400 dark:text-gray-600"
    role="contentinfo">
    <nav
      v-if="showNav"
      class="space-x-2"
      :aria-label="$t('footer-navigation')">
      <a
        :href="`https://${siteHost}`"
        class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
        rel="noopener noreferrer"
        :aria-label="$t('visit-onetime-secret-homepage')">
        {{ $t('powered-by-onetime-secret') }}
      </a>

      <template v-if="showTerms">
        <span
          aria-hidden="true"
          class="text-gray-400 dark:text-gray-600"
          >&middot;</span
        >
        <router-link
          to="/info/terms"
          class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          :aria-label="$t('view-terms-of-service')">
          {{ $t('terms') }}
        </router-link>
        <span aria-hidden="true">&middot;</span>
        <router-link
          to="/info/privacy"
          class="hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          :aria-label="$t('view-privacy-policy')">
          {{ $t('privacy') }}
        </router-link>
      </template>
    </nav>

    <div
      v-else
      class="text-center">
      <a
        :href="`https://${siteHost}`"
        class="text-[0.7rem] transition-colors duration-200 text-gray-400 hover:text-gray-500 hover:underline dark:text-gray-600 dark:hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
        rel="noopener noreferrer"
        :aria-label="$t('visit-onetime-secret-homepage')">
        {{ $t('powered-by-onetime-secret') }}
      </a>
    </div>
  </footer>
</template>
