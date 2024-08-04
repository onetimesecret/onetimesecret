<template>
  <div>
    <Icon
      v-if="mode === 'icon'"
      :icon="statusIcon"
      :class="[
        'w-5 h-5',
        { 'text-green-600': isActive, 'text-yellow-600': isWarning, 'text-red-600': isError }
      ]"
    />
    <div v-else class="bg-white dark:bg-gray-800 shadow-md rounded-lg p-6 my-8">
      <h2 class="text-2xl font-bold mb-4 text-gray-900 dark:text-white">Domain Status</h2>

      <div v-if="domain?.vhost" class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="flex flex-col">
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">Domain</span>
          <span class="text-lg font-semibold text-gray-900 dark:text-white">{{ domain?.vhost?.incoming_address }}</span>
        </div>

        <div class="flex flex-col">
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">Status</span>
          <span :class="statusColor" class="text-lg font-semibold">{{ domain?.vhost?.status_message }}</span>
        </div>

        <div class="flex flex-col">
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">Target Address</span>
          <span class="text-lg font-semibold text-gray-900 dark:text-white">{{ domain?.vhost?.target_address }}</span>
        </div>

        <div class="flex flex-col">
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">SSL Status</span>
          <span class="text-lg font-semibold" :class="domain?.vhost?.has_ssl ? 'text-green-600' : 'text-red-600'">
            {{ domain?.vhost?.has_ssl ? 'Active' : 'Inactive' }}
          </span>
        </div>

        <div class="flex flex-col">
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">SSL Renews</span>
          <span class="text-lg font-semibold text-gray-900 dark:text-white"><span v-if="domain?.vhost?.ssl_active_until">{{ formatDate(domain?.vhost?.ssl_active_until) }}</span></span>
        </div>

        <div class="flex flex-col">
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">Last Monitored</span>
          <span class="text-lg font-semibold text-gray-900 dark:text-white">{{ domain?.vhost?.last_monitored_humanized }}</span>
        </div>
      </div>

      <div class="mt-6">
        <h3 class="text-lg font-semibold mb-2 text-gray-900 dark:text-white">User Message</h3>
        <p class="text-gray-700 dark:text-gray-300">{{ domain?.vhost?.user_message }}</p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { computed } from 'vue';
import { CustomDomain } from '@/types/onetime'


interface Props {
  domain: CustomDomain;
  mode?: string;
}

const props = defineProps<Props>();

const isActive = computed(() => {
  return props.domain.vhost?.status?.includes('ACTIVE');
});

const isWarning = computed(() => {
  return props.domain.vhost?.status === 'DNS_INCORRECT';
});

const isError = computed(() => {
  return !isActive.value && !isWarning.value;
});

const statusIcon = computed(() => {
  if (isActive.value) return 'mdi:check-circle';
  if (isWarning.value) return 'mdi:alert-circle';
  return 'mdi:close-circle';
});

const statusColor = computed(() => {
  if (isActive.value) return 'text-green-600';
  if (isWarning.value) return 'text-yellow-600';
  return 'text-red-600';
});

const formatDate = (dateString: string): string => {
  const date = new Date(dateString);
  /**
   * About Intl.DateTimeFormat:
   *
   *  - It automatically respects the user's locale settings.
   *  - It handles internationalization correctly, using the appropriate
   *      date format for the user's locale.
   *  - It's more efficient than toLocaleDateString for repeated use, as
   *      you can reuse the formatter.
   */
  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  }).format(date);
};

</script>
