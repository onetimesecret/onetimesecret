<script setup lang="ts">
  import { useDomainStatus } from '@/composables/useDomainStatus';
  import { CustomDomain } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const props = defineProps<{
    domain: CustomDomain;
  }>();

  const { statusIcon, isActive, isWarning, isError, displayStatus } = useDomainStatus(
    props.domain
  );
</script>

<template>
  <div class="border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
    <div class="mx-auto max-w-7xl p-4 sm:px-6 lg:px-8">
      <!-- Back button section -->
      <div class="flex items-center space-x-4">
        <RouterLink
          to="/domains"
          class="inline-flex items-center text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"
          :aria-label="$t('return-to-domains-list')">
          <svg
            class="mr-2 size-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          {{ $t('back-to-domains') }}
        </RouterLink>
      </div>

      <!-- Title section - make text smaller on mobile -->
      <div
        v-if="domain"
        class="mt-4 flex flex-col gap-1">
        <div class="flex items-center justify-between gap-2">
          <div class="flex min-w-0 items-center gap-2">
            <h1
              class="flex min-w-0 items-center truncate text-2xl font-bold text-gray-900 dark:text-white sm:text-3xl">
              <span class="truncate">{{ domain.display_domain }}</span>
              <a
                :href="`https://${domain.display_domain}`"
                target="_blank"
                rel="noopener noreferrer"
                class="ml-1 text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300"
                :title="$t('open-domain-in-new-tab')">
                <OIcon
                  collection="mdi"
                  name="open-in-new"
                  class="size-5" />
              </a>
            </h1>
          </div>
          <div
            class="flex-shrink-0 flex items-center rounded-md bg-gray-100 px-3 py-1.5 dark:bg-gray-700">
            <RouterLink
              :to="`/domains/${domain?.display_domain}/verify`"
              class="inline-flex items-center gap-1.5"
              :data-tooltip="$t('web.domains.view-domain-verification-status')">
              <OIcon
                collection="mdi"
                :name="statusIcon"
                class="size-4 flex-shrink-0"
                :class="{
                  'text-emerald-600 dark:text-emerald-400': isActive,
                  'text-amber-500 dark:text-amber-400': isWarning,
                  'text-rose-600 dark:text-rose-500': isError,
                }" />
              <span class="text-sm font-brand leading-none">{{ t(displayStatus) }}</span>
            </RouterLink>
          </div>
        </div>
      </div>

      <div
        v-else
        class="mt-4 flex flex-col gap-1">
        <!-- Loading placeholder -->
        <div class="h-8 w-64 animate-pulse rounded bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-4 w-24 animate-pulse rounded bg-gray-200 dark:bg-gray-700"></div>
      </div>
    </div>
  </div>
</template>
