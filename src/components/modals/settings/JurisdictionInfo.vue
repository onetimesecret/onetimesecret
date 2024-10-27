<template>
  <div class="space-y-4">
    <div class="flex items-center gap-2">
      <Icon
        :icon="jurisdiction.icon"
        class="h-5 w-5 flex-shrink-0"
        aria-hidden="true"
      />
      <p class="text-gray-700 dark:text-gray-200 m-0">
        Your account and data are protected under the laws and regulations of
        <strong class="font-medium">{{ jurisdiction.display_name }}</strong>
      </p>
    </div>

    <p class="text-gray-600 dark:text-gray-300 m-0">
      This regulatory framework is determined by your access domain:
      <span class="px-2 py-1 bg-gray-100 font-bold dark:bg-gray-700 rounded text-base">
        {{ jurisdiction.domain }}
      </span>
    </p>

    <div class="space-y-2">
      <p class="text-gray-600 dark:text-gray-300 m-0">
        Each jurisdiction maintains separate legal compliance and data governance.
        While you can create accounts in multiple jurisdictions, they remain legally
        distinct with no data sharing between regulatory zones.
      </p>

      <p class="text-gray-600 dark:text-gray-300 m-0">
        To understand the specific regulations and protections that apply to your account,
        please
        <a
          :href="`${supportHost}/docs`"
          class="text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300 font-medium"
          target="_blank"
          rel="noopener noreferrer"
        >
          review our documentation
        </a>
        or
        <RouterLink
          to="/feedback"
          class="text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300 font-medium"
        >
          contact our compliance team
        </RouterLink>.
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import type { Jurisdiction } from '@/types';

defineProps<{
  jurisdiction: Jurisdiction;
  supportHost: string;
}>();
</script>
