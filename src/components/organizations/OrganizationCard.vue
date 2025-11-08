<!-- src/components/organizations/OrganizationCard.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import type { Organization } from '@/types/organization';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

defineProps<{
  organization: Organization;
}>();

const emit = defineEmits<{
  (e: 'click'): void;
}>();

const handleClick = () => {
  emit('click');
};
</script>

<template>
  <button
    type="button"
    @click="handleClick"
    class="group relative w-full rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-all hover:border-brand-500 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-brand-400 dark:focus:ring-brand-400"
  >
    <div class="flex items-start justify-between">
      <div class="min-w-0 flex-1">
        <h3
          class="truncate text-lg font-semibold text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400"
        >
          {{ organization.display_name }}
        </h3>
        <p
          v-if="organization.description"
          class="mt-1 line-clamp-2 text-sm text-gray-600 dark:text-gray-400"
        >
          {{ organization.description }}
        </p>
      </div>

      <OIcon
        collection="heroicons"
        name="chevron-right"
        class="ml-4 size-5 shrink-0 text-gray-400 transition-transform group-hover:translate-x-1 group-hover:text-brand-500 dark:text-gray-500 dark:group-hover:text-brand-400"
        aria-hidden="true"
      />
    </div>

    <div class="mt-4 flex items-center gap-3">
      <div class="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400">
        <OIcon
          collection="heroicons"
          name="building-office"
          class="size-4"
          aria-hidden="true"
        />
        <span>{{ t('web.organizations.organizations') }}</span>
      </div>
    </div>
  </button>
</template>
