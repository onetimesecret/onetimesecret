<!-- src/shared/components/modals/settings/JurisdictionInfo.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { Jurisdiction } from '@/schemas/models';

const { t } = useI18n();

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
        aria-hidden="true" />
      <p class="m-0 text-center text-gray-700 dark:text-gray-200 sm:text-left">
        {{ t('web.regions.your_account_and_data_are_protected_under_the_la') }}
        <strong class="font-medium">{{ jurisdiction.display_name }}</strong>
      </p>
    </div>

    <p class="m-0 text-center text-gray-600 dark:text-gray-300 sm:text-left">
      {{ t('web.regions.this_regulatory_framework_is_determined_by_your_') }}
      <span class="mt-2 block rounded bg-gray-100 px-2 py-1 text-base font-bold dark:bg-gray-700 sm:mt-0 sm:inline-block">
        {{ jurisdiction.domain }}
      </span>
    </p>

    <div class="space-y-2 sm:space-y-4">
      <p class="m-0 text-center text-gray-600 dark:text-gray-300 sm:text-left">
        {{ t('web.regions.each_jurisdiction_maintains_separate_legal_compl') }}
      </p>
    </div>
  </div>
</template>
