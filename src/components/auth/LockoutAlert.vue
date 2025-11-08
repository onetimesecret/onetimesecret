<script setup lang="ts">
import { computed } from 'vue';
import type { LockoutStatus } from '@/types/auth';

interface Props {
  lockout?: LockoutStatus | null;
}

const props = defineProps<Props>();

// Computed property for countdown display
const lockoutTimeRemaining = computed(() => {
  if (!props.lockout?.unlock_at) return '';

  const unlockTime = new Date(props.lockout.unlock_at);
  const now = new Date();
  const diff = unlockTime.getTime() - now.getTime();

  if (diff <= 0) return '';

  const minutes = Math.floor(diff / 60000);
  const seconds = Math.floor((diff % 60000) / 1000);

  if (minutes > 0) {
    return `${minutes}m ${seconds}s`;
  }
  return `${seconds}s`;
});

// Determine alert type and message
const isLocked = computed(() => props.lockout?.locked === true);
const hasAttemptsRemaining = computed(() =>
  props.lockout &&
  !isLocked.value &&
  props.lockout.attempts_remaining !== undefined
);
</script>

<template>
  <div v-if="lockout">
    <!-- Account is locked -->
    <div
      v-if="isLocked"
      role="alert"
      class="mb-4 rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
    >
      <div class="flex items-start">
        <i class="fas fa-lock mr-3 mt-0.5 text-red-600 dark:text-red-400"></i>
        <div class="flex-1">
          <h3 class="font-semibold text-red-800 dark:text-red-300">
            {{ $t('web.auth.lockout.account-locked') }}
          </h3>
          <p class="mt-1 text-sm text-red-700 dark:text-red-400">
            <span v-if="lockout.unlock_at">
              {{ $t('web.auth.lockout.locked-until', { time: lockoutTimeRemaining }) }}
            </span>
          </p>
          <div class="mt-3 space-y-1 text-sm text-red-700 dark:text-red-400">
            <p>{{ $t('web.auth.lockout.try-password-reset') }}</p>
            <p class="text-xs">{{ $t('web.auth.lockout.contact-support') }}</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Warning: attempts remaining -->
    <div
      v-else-if="hasAttemptsRemaining"
      role="alert"
      class="mb-4 rounded-lg bg-yellow-50 p-4 dark:bg-yellow-900/20"
    >
      <div class="flex items-start">
        <i class="fas fa-exclamation-triangle mr-3 mt-0.5 text-yellow-600 dark:text-yellow-400"></i>
        <div class="flex-1">
          <p class="font-medium text-yellow-800 dark:text-yellow-300">
            {{ $t('web.auth.lockout.attempts-remaining', { count: lockout.attempts_remaining }) }}
          </p>
          <p class="mt-1 text-sm text-yellow-700 dark:text-yellow-400">
            {{ $t('web.auth.lockout.try-password-reset') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
