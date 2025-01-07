// src/stores/notificationsStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';

export type NotificationPosition = 'top' | 'bottom';
export type NotificationSeverity = 'success' | 'error' | 'info' | 'warning' | null;

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for NotificationsStore.
 */
export type NotificationsStore = {
  // State
  message: string;
  severity: NotificationSeverity;
  isVisible: boolean;
  position: NotificationPosition;
  _initialized: boolean;

  // Actions
  init: () => void;
  show: (
    msg: string,
    sev: 'success' | 'error' | 'info',
    pos?: NotificationPosition
  ) => void;
  hide: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing global notification state and behaviors
 */
export const useNotificationsStore = defineStore('notifications', () => {
  const $api = inject('api') as AxiosInstance; // eslint-disable-line

  // State
  const message = ref('');
  const severity = ref<NotificationSeverity>(null);
  const isVisible = ref(false);
  const position = ref<NotificationPosition>('bottom');
  const _initialized = ref(false);

  function init(options?: StoreOptions) {
    if (_initialized.value) return;

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;
  }

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
    init,

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
