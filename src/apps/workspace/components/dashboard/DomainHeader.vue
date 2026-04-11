<!-- src/apps/workspace/components/dashboard/DomainHeader.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useDomainStatus } from '@/shared/composables/useDomainStatus';
  import { CustomDomain } from '@/schemas/shapes/v3';
  import { computed } from 'vue';

const { t } = useI18n();

  const props = defineProps<{
    domain: CustomDomain | null;
    hasUnsavedChanges: boolean;
    orgid: string;
  }>();

  const verifyRoute = computed(() => `/org/${props.orgid}/domains/${props.domain?.extid}/verify`);

  const { statusIcon, isActive, isWarning, isError, displayStatus } = useDomainStatus(
    () => props.domain
  );
</script>

<template>
  <div class="border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
    <div class="mx-auto max-w-7xl p-4 sm:px-6 lg:px-8">
      <!-- Title section - make text smaller on mobile -->
      <div
        v-if="domain"
        class="mt-4 flex flex-col gap-1">
        <div class="flex items-center justify-between gap-2">
          <div class="flex min-w-0 items-center gap-2">
            <!-- prettier-ignore-attribute class -->
            <h1
              class="flex min-w-0 items-center truncate text-2xl font-bold
                text-gray-900 dark:text-white sm:text-3xl">
              <span class="truncate">{{ domain.display_domain }}</span>
              <!-- prettier-ignore-attribute class -->
              <a
                :href="`https://${domain.display_domain}`"
                target="_blank"
                v-show="!hasUnsavedChanges"
                rel="noopener noreferrer"
                class="ml-1
                  text-gray-400 hover:text-gray-600
                  dark:text-gray-500 dark:hover:text-gray-300"
                :title="t('web.domains.open_domain_in_new_tab')">
                <OIcon
                  collection="mdi"
                  name="open-in-new"
                  class="size-5" />
              </a>
            </h1>
          </div>
          <!-- prettier-ignore-attribute class -->
          <div
            class="flex shrink-0 items-center rounded-md
              bg-gray-100 px-3 py-1.5 dark:bg-gray-700">
            <RouterLink
              :to="verifyRoute"
              class="inline-flex items-center gap-1.5"
              :data-tooltip="t('web.domains.view_domain_verification_status')">
              <OIcon
                collection="mdi"
                :name="statusIcon"
                class="size-4 shrink-0"
                :class="{
                  'text-emerald-600 dark:text-emerald-400': isActive,
                  'text-amber-500 dark:text-amber-400': isWarning,
                  'text-rose-600 dark:text-rose-500': isError,
                }" />
              <span class="font-brand text-sm leading-none">{{ displayStatus }}</span>
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
