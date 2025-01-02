// src/stores/notificationsStore.ts
import { defineStore } from 'pinia';
import { ref } from 'vue';

type NotificationPosition = 'top' | 'bottom';
type NotificationSeverity = 'success' | 'error' | 'info' | 'warning' | null;

/**
 * Store for managing global notification state and behaviors
 */
export const useNotificationsStore = defineStore('notifications', () => {
  // State
  const message = ref('');
  const severity = ref<NotificationSeverity>(null);
  const isVisible = ref(false);
  const position = ref<NotificationPosition>('bottom');
  const _initialized = ref(false);

  /**
   * Display a notification message with specified settings
   * @param msg - The message to display
   * @param sev - Severity level of the notification
   * @param pos - Optional position of notification
   */
  function show(msg: string, sev: 'success' | 'error' | 'info', pos?: 'top' | 'bottom') {
    message.value = msg;
    severity.value = sev;
    position.value = pos || 'bottom';
    isVisible.value = true;

    setTimeout(() => {
      hide();
    }, 5000);
  }

  /**
   * Hide the current notification and reset its state
   */
  function hide() {
    isVisible.value = false;
    message.value = '';
    severity.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    message.value = '';
    severity.value = null;
    isVisible.value = false;
    position.value = 'bottom';
    _initialized.value = false;
  }

  return {
    // State
    message,
    severity,
    isVisible,
    position,
    _initialized,

    // Actions
    show,
    hide,
    $reset,
  };
});
