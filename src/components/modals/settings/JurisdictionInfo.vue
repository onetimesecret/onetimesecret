<script setup lang="ts">
import type { Jurisdiction } from '@/schemas/models';
import OIcon from '@/components/icons/OIcon.vue';

defineProps<{
  jurisdiction: Jurisdiction;
}>();
</script>

<template>
  <div class="space-y-4 sm:space-y-6">
    <div class="flex flex-col items-center gap-2 sm:flex-row">
      <OIcon
        :collection="jurisdiction.icon.collection"
        :name="jurisdiction.icon.name"
        class="size-5 shrink-0"
        aria-hidden="true"
      />
      <p class="m-0 text-center text-gray-700 dark:text-gray-200 sm:text-left">
        {{ $t('your-account-and-data-are-protected-under-the-la') }}
        <strong class="font-medium">{{ jurisdiction.display_name }}</strong>
      </p>
    </div>

    <p class="m-0 text-center text-gray-600 dark:text-gray-300 sm:text-left">
      {{ $t('this-regulatory-framework-is-determined-by-your-') }}
      <span class="mt-2 block rounded bg-gray-100 px-2 py-1 text-base font-bold dark:bg-gray-700 sm:mt-0 sm:inline-block">
        {{ jurisdiction.domain }}
      </span>
    </p>

    <div class="space-y-2 sm:space-y-4">
      <p class="m-0 text-center text-gray-600 dark:text-gray-300 sm:text-left">
        {{ $t('each-jurisdiction-maintains-separate-legal-compl') }}
      </p>

      <p class="m-0 text-center text-gray-600 dark:text-gray-300 sm:text-left">
        {{ $t('to-understand-the-specific-regulations-and-prote') }}
        <RouterLink
          to="/docs"
          class="font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300"
          target="_blank"
          rel="noopener noreferrer">
          {{ $t('review-our-documentation') }}
        </RouterLink>
        or
        <RouterLink
          to="/feedback"
          class="font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          {{ $t('contact-our-compliance-team') }}
        </RouterLink>.
      </p>
    </div>
  </div>
</template>
