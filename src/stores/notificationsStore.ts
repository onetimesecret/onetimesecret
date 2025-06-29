// src/stores/notificationsStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia';
import { loggingService } from '@/services/logging.service';
import { NotificationSeverity } from '@/types/ui/notifications';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';
import { WindowService } from '@/services/window.service';

export type NotificationPosition = 'top' | 'bottom';

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
  show: (msg: string, sev: 'success' | 'error' | 'info', pos?: NotificationPosition) => void;
  hide: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Manifold notification management store integrated with server-side messages
 *
 * Handles application-wide notifications including success messages,
 * errors, and info alerts. Provides auto-dismissal and position control.
 *
 * Architecture:
 * - Initializes from server messages on mount
 * - Manages client-only state after initialization
 * - No direct coupling with SessionMessages module
 *
 * @example Initialize and handle server messages
 * ```ts
 * const store = useNotificationsStore();
 * store.init(); // Processes window.messages
 * ```
 *
 * @example Client-side notification
 * ```ts
 * store.show('Operation completed', 'success', 'top');
 * ```
 */
/* eslint-disable max-lines-per-function */
export const useNotificationsStore = defineStore('notifications', () => {
  const $api = inject('api') as AxiosInstance; // eslint-disable-line

  // State refs with default values
  const message = ref('');
  const severity = ref<NotificationSeverity>(null);
  const isVisible = ref(false);
  const position = ref<NotificationPosition>('bottom');
  const _initialized = ref(false);

  /**
   * Initialize notification store
   * @param options - Optional store configuration
   */
  function init(options?: StoreOptions) {
    if (_initialized.value) return;

    if (options?.api) {
      loggingService.warn('API instance provided in options, ignoring.');
    }

    const serverMessages = WindowService.get('messages');
    if (!serverMessages?.length) return;

    // Get last error or info message
    const messages = [...serverMessages].reverse();
    const errorMessage = messages.find((msg) => msg.type === 'error');
    const successMessage = messages.find((msg) => msg.type === 'success');
    const infoMessage = messages.find((msg) => msg.type === 'info');

    // Display error message with priority over info
    if (errorMessage) {
      show(errorMessage.content, 'error');
    } else if (successMessage) {
      show(successMessage.content, 'success');
    } else if (infoMessage) {
      show(infoMessage.content, 'info');
    }

    _initialized.value = true;
  }

  /**
   * Display notification with auto-dismissal
   *
   * @param msg - Notification message text
   * @param sev - Message severity: 'success' | 'error' | 'info'
   * @param pos - Optional display position, defaults to 'bottom'
   *
   * @example Error Notification
   * ```ts
   * show('Failed to save', 'error');
   * ```
   *
   * @example Success with Position
   * ```ts
   * show('Changes saved', 'success', 'top');
   * ```
   */
  function show(msg: string, sev: NotificationSeverity, pos?: NotificationPosition) {
    message.value = msg;
    severity.value = sev;
    position.value = pos || 'bottom';
    isVisible.value = true;

    setTimeout(() => {
      hide();
    }, 5000);
  }

  /**
   * Hide current notification and reset state
   *
   * @example
   * ```ts
   * // Manually dismiss notification
   * notifications.hide();
   * ```
   */
  function hide() {
    isVisible.value = false;
    message.value = '';
    severity.value = null;
  }

  /**
   * Reset store to initial state
   * Clears message, severity, visibility and position
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
