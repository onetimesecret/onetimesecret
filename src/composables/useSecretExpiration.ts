// src/composables/useSecretExpiration.ts
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { formatDistance, isValid } from 'date-fns';

export function useSecretExpiration(created: Date, ttlSeconds: number) {
  if (!isValid(created)) {
    throw new Error('Invalid creation date');
  }
  if (typeof ttlSeconds !== 'number' || ttlSeconds <= 0) {
    throw new Error('Invalid TTL');
  }

  const progress = ref(0);
  const timeRemaining = ref('');

  // Convert TTL to milliseconds for consistency
  const ttlMs = ttlSeconds * 1000;

  // Calculate absolute expiration time
  const expirationDate = computed(() => new Date(created.getTime() + ttlMs));

  const updateExpiration = () => {
    const now = new Date();
    const end = expirationDate.value;
    const total = ttlMs;
    const elapsed = now.getTime() - created.getTime();

    if (now >= end) {
      progress.value = 100;
      timeRemaining.value = 'Expired';
      return;
    }

    progress.value = Math.min(100, Math.max(0, (elapsed / total) * 100));

    // Format remaining time
    timeRemaining.value = formatDistance(end, now, {
      addSuffix: true,
      includeSeconds: elapsed < 60000, // Only show seconds in last minute
    });
  };

  let timer: number;
  onMounted(() => {
    updateExpiration();
    timer = window.setInterval(updateExpiration, 60000);
  });

  onUnmounted(() => clearInterval(timer));

  return {
    progress,
    timeRemaining,
    expirationDate,
  };
}
