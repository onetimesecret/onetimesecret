// src/shared/stores/notificationsStore.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { NotificationSeverity } from '@/types/ui/notifications';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties, storeToRefs } from 'pinia';
import { inject, nextTick, ref } from 'vue';

export type NotificationPosition = 'top' | 'bottom';


/**
 * Type definition for NotificationsStore.
 */
export type NotificationsStore = {
  // State
  message: string;
  severity: NotificationSeverity;
  isVisible: boolean;
  position: NotificationPosition;
  duration: number;
  _initialized: boolean;

  // Actions
  init: () => void;
  show: (msg: string, sev: 'success' | 'error' | 'info', pos?: NotificationPosition, dur?: number) => void;
  enqueue: (msg: string, sev: 'success' | 'error' | 'info', pos?: NotificationPosition, dur?: number) => void;
  hide: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

const DEFAULT_AUTO_HIDE_MS = 5000;

/**
 * Upper bound on notices waiting behind the visible one. Three is already
 * more than a user will read in sequence; past that the app is flooding, and
 * holding more would only delay the ones that were accepted first.
 */
const MAX_PENDING = 3;

interface PendingNotice {
  msg: string;
  sev: NotificationSeverity;
  pos?: NotificationPosition;
  dur?: number;
}

/**
 * Frontend notification management store integrated with server-side messages
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

// eslint-disable-next-line max-lines-per-function, max-statements
export const useNotificationsStore = defineStore('notifications', () => {
  const $api = inject('api') as AxiosInstance; // eslint-disable-line
  const bootstrapStore = useBootstrapStore();
  const { messages: bootstrapMessages } = storeToRefs(bootstrapStore);

  // State refs with default values
  const message = ref('');
  const severity = ref<NotificationSeverity>(null);
  const isVisible = ref(false);
  const position = ref<NotificationPosition>('top');
  const duration = ref(DEFAULT_AUTO_HIDE_MS);
  const _initialized = ref(false);
  let _hideTimerId: ReturnType<typeof setTimeout> | null = null;
  // Notices waiting for the visible one to clear. Plain array, not a ref: the
  // host renders only the visible slot and nothing else needs to react to it.
  const _pending: PendingNotice[] = [];
  let _drainScheduled = false;

  /**
   * Initialize notification store
   * @param options - Optional store configuration
   */
  function init() {
    if (_initialized.value) return;

    const serverMessages = bootstrapMessages.value;
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

  /** Display a notification with auto-dismissal. Defaults to 5 s; pass 0 or negative to disable. */
  function show(
    msg: string,
    sev: NotificationSeverity,
    pos?: NotificationPosition,
    dur?: number
  ) {
    // Clear any pending hide timer so earlier timeouts don't dismiss this message
    if (_hideTimerId !== null) {
      clearTimeout(_hideTimerId);
      _hideTimerId = null;
    }

    message.value = msg;
    severity.value = sev;
    position.value = pos || 'top';

    const ms = dur ?? DEFAULT_AUTO_HIDE_MS;
    duration.value = ms;
    isVisible.value = true;
    if (ms > 0) {
      _hideTimerId = setTimeout(() => {
        hide();
      }, ms);
    }
  }

  /**
   * Show a notification without displacing one already on screen.
   *
   * Idle store: identical to show(). Otherwise the notice waits and is shown
   * when the visible one clears, whether its timer fires or hide() is called
   * (the host's dismiss button). A sticky notice (duration <= 0) holds the
   * queue until hide(): there is no timer to drain it, and the sticky notice
   * was made sticky because the user has to see it.
   *
   * The queue is bounded by MAX_PENDING; once full the newest arrival is
   * refused rather than evicting an earlier one, so a caller that was accepted
   * stays accepted. A message whose text matches the visible notice or one
   * already waiting is skipped: the guards and App.vue can re-raise the same
   * explanation on consecutive navigations, and repeating it is noise.
   *
   * show() keeps its replace-immediately semantics and leaves the queue alone.
   */
  function enqueue(
    msg: string,
    sev: NotificationSeverity,
    pos?: NotificationPosition,
    dur?: number
  ) {
    // A hidden store with notices still pending is mid-drain (see hide()):
    // the new arrival joins the line instead of jumping it.
    if (!isVisible.value && _pending.length === 0) {
      show(msg, sev, pos, dur);
      return;
    }
    if (message.value === msg) return;
    if (_pending.some((entry) => entry.msg === msg)) return;
    if (_pending.length >= MAX_PENDING) return;
    _pending.push({ msg, sev, pos, dur });
  }

  /**
   * Hide the current notification, then show the next queued one if any.
   *
   * The drain waits for the next tick so the host renders the hidden state in
   * between. Showing the next notice synchronously would flip isVisible back
   * to true before Vue flushes, and the toast's Transition and progress-bar
   * animation would never observe the change: the queued text would swap in
   * place with no enter animation, which is easy to miss.
   */
  function hide() {
    if (_hideTimerId !== null) {
      clearTimeout(_hideTimerId);
      _hideTimerId = null;
    }
    isVisible.value = false;
    message.value = '';
    severity.value = null;
    duration.value = DEFAULT_AUTO_HIDE_MS;

    if (_pending.length === 0 || _drainScheduled) return;
    _drainScheduled = true;
    void nextTick(() => {
      _drainScheduled = false;
      // show() or enqueue() put something on screen in the meantime; the
      // queue drains when that notice clears. $reset() empties the queue.
      if (isVisible.value) return;
      const next = _pending.shift();
      if (next) show(next.msg, next.sev, next.pos, next.dur);
    });
  }

  /** Reset store to initial state (clears message, severity, visibility, position, queue). */
  function $reset() {
    if (_hideTimerId !== null) {
      clearTimeout(_hideTimerId);
      _hideTimerId = null;
    }
    _pending.length = 0;
    message.value = '';
    severity.value = null;
    isVisible.value = false;
    position.value = 'top';
    duration.value = DEFAULT_AUTO_HIDE_MS;
    _initialized.value = false;
  }

  return {
    init,

    // State
    message,
    severity,
    isVisible,
    position,
    duration,
    _initialized,

    // Actions
    show,
    enqueue,
    hide,
    $reset,
  };
});
