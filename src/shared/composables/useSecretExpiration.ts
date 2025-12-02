// src/shared/composables/useSecretExpiration.ts

import { formatDistance } from 'date-fns';
import { ref, computed, onMounted, onUnmounted } from 'vue';

export const EXPIRATION_EVENTS = {
  EXPIRED: 'expired',
  WARNING: 'warning',
  UPDATED: 'updated',
} as const;

export function useSecretExpiration(created: Date, ttlSeconds: number) {
  const progress = ref(0);
  const timeRemaining = ref('');
  const expirationState = ref<'active' | 'warning' | 'expired'>('active');
  const expirationDate = computed(() => new Date(created.getTime() + ttlSeconds * 1000));

  const emitter = new EventTarget();

  const updateExpiration = () => {
    const now = new Date();
    const end = expirationDate.value;
    const elapsed = now.getTime() - created.getTime();
    const total = ttlSeconds * 1000;
    const remaining = total - elapsed;
    const newProgress = Math.min(100, Math.max(0, (elapsed / total) * 100));

    // Determine warning threshold based on TTL
    const warningThreshold = getWarningThreshold(ttlSeconds);
    const warningMs = warningThreshold * 1000;

    // Detect state transitions
    if (newProgress >= 100 && expirationState.value !== 'expired') {
      expirationState.value = 'expired';
      emitter.dispatchEvent(new CustomEvent(EXPIRATION_EVENTS.EXPIRED));
      clearInterval(timer);
    } else if (remaining <= warningMs && expirationState.value === 'active') {
      expirationState.value = 'warning';
      emitter.dispatchEvent(new CustomEvent(EXPIRATION_EVENTS.WARNING));
    }

    progress.value = newProgress;
    timeRemaining.value = formatDistance(end, now, {
      addSuffix: true,
      includeSeconds: elapsed < 60000,
    });

    emitter.dispatchEvent(
      new CustomEvent(EXPIRATION_EVENTS.UPDATED, {
        detail: { progress: progress.value, timeRemaining: timeRemaining.value },
      })
    );
  };

  // Expose subscription method
  const onExpirationEvent = (
    event: (typeof EXPIRATION_EVENTS)[keyof typeof EXPIRATION_EVENTS],
    handler: (e: CustomEvent) => void
  ) => {
    emitter.addEventListener(event, handler as EventListener);
    return () => emitter.removeEventListener(event, handler as EventListener);
  };

  let timer: number;
  onMounted(() => {
    updateExpiration();
    // Update every second for smooth progress
    // TODO: Update less often when time remaining is large
    timer = window.setInterval(updateExpiration, 1000);
  });

  onUnmounted(() => clearInterval(timer));

  return {
    progress,
    timeRemaining,
    expirationDate: computed(() => new Date(created.getTime() + ttlSeconds * 1000)),
    expirationState,
    onExpirationEvent,
  };
}

// Time constants in seconds
const ONE_MINUTE = 60;
const FIVE_MINUTES = ONE_MINUTE * 5;
const ONE_HOUR = ONE_MINUTE * 60;
const THREE_HOURS = ONE_HOUR * 3;
const ONE_DAY = ONE_HOUR * 24;

// Calculate warning threshold based on total TTL
function getWarningThreshold(ttlSeconds: number): number {
  // Warning thresholds for different TTL ranges
  const thresholds = [
    { remainingTtl: FIVE_MINUTES, warning: ONE_MINUTE },
    { remainingTtl: ONE_HOUR, warning: FIVE_MINUTES },
    { remainingTtl: ONE_DAY, warning: ONE_HOUR },
    { remainingTtl: Infinity, warning: THREE_HOURS },
  ];

  return thresholds.find((t) => ttlSeconds <= t.remainingTtl)?.warning ?? ONE_HOUR;
}
