<script setup lang="ts">
import { computed } from 'vue';
import type { Session } from '@/types/auth';

interface Props {
  session: Session;
  isCurrent: boolean;
}

const props = defineProps<Props>();
const emit = defineEmits<{
  remove: [sessionId: string];
}>();

// Parse user agent to extract browser/device info
const deviceInfo = computed(() => {
  const ua = props.session.user_agent || 'Unknown Device';

  // Simple parsing - can be enhanced with a library like ua-parser-js
  if (ua.includes('Chrome')) return 'Chrome';
  if (ua.includes('Firefox')) return 'Firefox';
  if (ua.includes('Safari') && !ua.includes('Chrome')) return 'Safari';
  if (ua.includes('Edge')) return 'Edge';
  if (ua.includes('Mobile')) return 'Mobile Browser';

  return 'Unknown Browser';
});

// Format last activity time
const lastActiveFormatted = computed(() => {
  const date = new Date(props.session.last_activity_at);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins} minute${diffMins > 1 ? 's' : ''} ago`;
  if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
  if (diffDays < 7) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;

  return date.toLocaleDateString();
});

// Format creation time
const createdFormatted = computed(() => new Date(props.session.created_at).toLocaleDateString());

const handleRemove = () => {
  emit('remove', props.session.id);
};
</script>

<template>
  <div
    class="flex flex-col gap-4 rounded-lg border p-4 dark:border-gray-600"
    :class="{
      'border-brand-500 bg-brand-50 dark:bg-brand-900/20': isCurrent,
      'border-gray-200 bg-white dark:bg-gray-800': !isCurrent,
    }"
  >
    <div class="flex items-start justify-between">
      <div class="flex-1">
        <!-- Device/Browser info -->
        <div class="flex items-center gap-2">
          <i class="fas fa-desktop text-gray-600 dark:text-gray-400"></i>
          <h3 class="font-semibold dark:text-white">
            {{ deviceInfo }}
          </h3>
          <span
            v-if="isCurrent"
            class="rounded-full bg-brand-100 px-2 py-0.5 text-xs font-medium text-brand-800 dark:bg-brand-900 dark:text-brand-200"
          >
            {{ $t('web.auth.sessions.current') }}
          </span>
          <span
            v-if="session.remember_enabled"
            class="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-800 dark:bg-blue-900 dark:text-blue-200"
          >
            <i class="fas fa-clock mr-1"></i>
            {{ $t('web.auth.remember.enabled') }}
          </span>
        </div>

        <!-- Session details -->
        <div class="mt-2 space-y-1 text-sm text-gray-600 dark:text-gray-400">
          <div v-if="session.ip_address" class="flex items-center gap-2">
            <i class="fas fa-map-marker-alt w-4 text-xs"></i>
            <span>{{ $t('web.auth.sessions.ip-address') }}: {{ session.ip_address }}</span>
          </div>
          <div class="flex items-center gap-2">
            <i class="fas fa-clock w-4 text-xs"></i>
            <span>{{ $t('web.auth.sessions.last-active') }}: {{ lastActiveFormatted }}</span>
          </div>
          <div class="flex items-center gap-2">
            <i class="fas fa-calendar w-4 text-xs"></i>
            <span>{{ $t('web.auth.sessions.created') }}: {{ createdFormatted }}</span>
          </div>
        </div>
      </div>

      <!-- Remove button (only for non-current sessions) -->
      <button
        v-if="!isCurrent"
        @click="handleRemove"
        type="button"
        class="ml-4 rounded-md px-3 py-1 text-sm font-medium text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:text-red-400 dark:hover:bg-red-900/20"
        :aria-label="$t('web.auth.sessions.remove')"
      >
        <i class="fas fa-times mr-1"></i>
        {{ $t('web.auth.sessions.remove') }}
      </button>
    </div>

    <!-- Full user agent (collapsed by default, can be expanded) -->
    <details v-if="session.user_agent" class="text-xs text-gray-500 dark:text-gray-500">
      <summary class="cursor-pointer hover:text-gray-700 dark:hover:text-gray-400">
        View user agent
      </summary>
      <p class="mt-1 break-all font-mono">{{ session.user_agent }}</p>
    </details>
  </div>
</template>
