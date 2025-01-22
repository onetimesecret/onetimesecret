<script setup lang="ts">
import { useNotificationsStore } from '@/stores/notificationsStore';
import OIcon from '@/components/icons/OIcon.vue';
import { computed } from 'vue';

interface Props {
  autoDismiss?: boolean;
  duration?: number;
  loading?: boolean;
  position?: 'top' | 'bottom';
}

const props = withDefaults(defineProps<Props>(), {
  autoDismiss: true,
  duration: 4000,
  loading: false,
  position: 'bottom'
});

const notifications = useNotificationsStore();

// Add a computed property for the effective position
const effectivePosition = computed(() => {
  // Store position takes precedence if it exists
  return notifications.position || props.position;
});

const getStatusConfig = (type: string | null) => ({
  success: {
    icon: 'check-circle',
    classes: 'bg-green-50 dark:bg-green-900',
    textClasses: 'text-green-700 dark:text-green-100',
    iconClasses: 'text-green-500 dark:text-green-300'
  },
  error: {
    icon: 'alert-circle',
    classes: 'bg-red-50 dark:bg-red-900',
    textClasses: 'text-red-700 dark:text-red-100',
    iconClasses: 'text-red-500 dark:text-red-300'
  },
  warning: {
    icon: 'alert',
    classes: 'bg-amber-50 dark:bg-amber-900',
    textClasses: 'text-amber-700 dark:text-amber-100',
    iconClasses: 'text-amber-500 dark:text-amber-300'
  },
  info: {
    icon: 'information',
    classes: 'bg-blue-50 dark:bg-blue-900',
    textClasses: 'text-blue-700 dark:text-blue-100',
    iconClasses: 'text-blue-500 dark:text-blue-300'
  },
  loading: {
    icon: 'loading',
    classes: 'bg-blue-50 dark:bg-blue-900',
    textClasses: 'text-blue-700 dark:text-blue-100',
    iconClasses: 'text-blue-500 dark:text-blue-300 animate-spin'
  },
})[type || 'info'];

const statusConfig = computed(() => {
  if (props.loading) {
    return getStatusConfig('loading');
  }
  return getStatusConfig(notifications.severity);
});
</script>


<script lang="ts">
/**
 * StatusBar Component
 *
 * A floating status bar that displays notifications from the notifications store.
 * Uses portal/teleport to render outside the normal DOM flow at the bottom of the viewport.
 *
 * Features:
 * - Loading, success, error, and info states with appropriate styling
 * - Auto-dismiss with visual progress indicator
 * - Smooth transitions between states
 * - Dark mode support
 * - Accessible aria attributes
 * - Centralized notification management via Pinia store
 *
 * Portal Target:
 * Component teleports to the <body> tag by default. For custom positioning,
 * add a target element:
 * <div id="status-messages"></div>
 * Then update the Teleport "to" prop accordingly:
 * <StatusBar to="#status-messages" />
 *
 * @example
 * <!-- Component usage -->
 * <StatusBar :loading="formState.loading" />
 *
 * <!-- Show notifications via store -->
 * const notifications = useNotificationsStore();
 * notifications.show('Success message', 'success');
 * notifications.show('Error message', 'error');
 * notifications.show('Info message', 'info');
 *
 * @prop {boolean} [loading] - Whether to show loading state
 * @prop {boolean} [autoDismiss=true] - Whether to auto-dismiss after duration
 * @prop {number} [duration=5000] - Time in ms before auto-dismiss
 */
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transform ease-out duration-300 transition"
      :enter-from-class="effectivePosition === 'top'
        ? '-translate-y-2 opacity-0 sm:-translate-y-0 sm:translate-x-2'
        : 'translate-y-2 opacity-0 sm:translate-y-0 sm:translate-x-2'"
      enter-to-class="translate-y-0 opacity-100 sm:translate-x-0"
      leave-active-class="transition ease-in duration-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0">
      <div
        v-if="notifications.isVisible"
        class="fixed inset-x-0 flex items-center justify-between px-4 py-3 shadow-lg transition-colors duration-200 z-50"
        :class="[
          statusConfig?.classes,
          effectivePosition === 'top' ? 'top-0' : 'bottom-0'
        ]"
        role="status"
        aria-live="polite">
        <div class="flex items-center space-x-3">
          <OIcon
            collection="mdi"
            :name="statusConfig?.icon || 'information'"
            class="size-5 transition-all duration-200"
            :class="statusConfig?.iconClasses"
            aria-hidden="true"
          />
          <span
            class="text-sm font-medium transition-all duration-200"
            :class="statusConfig?.textClasses">
            {{ notifications.message }}
          </span>
        </div>

        <div class="flex items-center">
          <button
            v-if="!loading"
            type="button"
            class="ml-4 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
            @click="notifications.hide">
            <span class="sr-only">Dismiss</span>
            <OIcon
              collection="mdi"
              name="close"
              class="size-5"
            />
          </button>
        </div>

        <!-- Progress indicator -->
        <div
          v-if="autoDismiss && !loading && notifications.severity"
          class="absolute h-1 bg-current opacity-30"
          :class="[
            (effectivePosition === 'top' ? 'bottom-0' : 'top-0'),
            statusConfig?.textClasses
          ]"
          :style="{
            animation: `shrink ${duration}ms linear forwards`
          }"></div>
      </div>
    </Transition>
  </Teleport>
</template>

<style>
@keyframes shrink {
  from {
    width: 100%;
  }

  to {
    width: 0%;
  }
}
</style>
