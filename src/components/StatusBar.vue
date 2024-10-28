
<template>
  <Teleport to="body">
    <TransitionRoot
      :show="isVisible || loading"
      appear
      enter="transition-all duration-200 ease-out"
      enter-from="transform translate-y-full opacity-0"
      enter-to="transform translate-y-0 opacity-100"
      leave="transition-all duration-150 ease-in"
      leave-from="transform translate-y-0 opacity-100"
      leave-to="transform translate-y-full opacity-0"
    >
      <div
        class="fixed bottom-0 left-0 right-0 flex items-center justify-between px-4 py-3 shadow-lg transition-colors duration-200"
        :class="preloadStatus?.classes"
        role="status"
        aria-live="polite"
      >
        <div class="flex items-center space-x-3">
          <Icon
            :icon="preloadStatus?.icon || 'mdi:information'"
            class="h-5 w-5 transition-all duration-200"
            :class="preloadStatus?.iconClasses"
            aria-hidden="true"
          />
          <span
            class="text-sm font-medium transition-all duration-200"
            :class="preloadStatus?.textClasses"
          >
            {{ message }}
          </span>
        </div>

        <div class="flex items-center">
          <button
            v-if="!loading"
            type="button"
            class="ml-4 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
            @click="handleDismiss"
          >
            <span class="sr-only">Dismiss</span>
            <Icon icon="mdi:close" class="h-5 w-5" />
          </button>
        </div>

        <!-- Progress indicator only shows after loading is complete -->
        <div
          v-if="autoDismiss && !loading && (success || error)"
          class="absolute bottom-0 left-0 h-1 bg-current opacity-30"
          :style="{
            animation: `shrink ${duration}ms linear forwards`
          }"
        />
      </div>
    </TransitionRoot>
  </Teleport>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { TransitionRoot } from '@headlessui/vue';
import { ref, onMounted, watch, computed, onBeforeUnmount } from 'vue';

export type StatusType = 'success' | 'error' | 'warning' | 'info';

interface Props {
  success?: string;
  error?: string;
  autoDismiss?: boolean;
  duration?: number;
  loading?: boolean; // Add loading prop to sync with form state
}

const props = withDefaults(defineProps<Props>(), {
  autoDismiss: true,
  duration: 5000,
  loading: false
});

const emit = defineEmits<{
  (e: 'dismiss'): void;
}>();

const isVisible = ref(false);
const dismissTimer = ref<number | null>(null);

const getStatusConfig = (type: StatusType) => ({
  success: {
    icon: 'mdi:check-circle',
    classes: 'bg-green-50 dark:bg-green-900',
    textClasses: 'text-green-700 dark:text-green-100',
    iconClasses: 'text-green-500 dark:text-green-300'
  },
  error: {
    icon: 'mdi:alert-circle',
    classes: 'bg-red-50 dark:bg-red-900',
    textClasses: 'text-red-700 dark:text-red-100',
    iconClasses: 'text-red-500 dark:text-red-300'
  },
  warning: {
    icon: 'mdi:alert',
    classes: 'bg-yellow-50 dark:bg-yellow-900',
    textClasses: 'text-yellow-700 dark:text-yellow-100',
    iconClasses: 'text-yellow-500 dark:text-yellow-300'
  },
  info: {
    icon: 'mdi:information',
    classes: 'bg-blue-50 dark:bg-blue-900',
    textClasses: 'text-blue-700 dark:text-blue-100',
    iconClasses: 'text-blue-500 dark:text-blue-300'
  }
})[type];

const currentStatus = computed(() => {
  if (props.success) return getStatusConfig('success');
  if (props.error) return getStatusConfig('error');
  return null;
});

const message = computed(() => {
  if (props.loading) return 'Saving changes...';
  return props.success || props.error || '';
});

const startDismissTimer = () => {
  if (!props.autoDismiss) return;

  dismissTimer.value = window.setTimeout(() => {
    isVisible.value = false;
    emit('dismiss');
  }, props.duration);
};

const clearDismissTimer = () => {
  if (dismissTimer.value) {
    clearTimeout(dismissTimer.value);
    dismissTimer.value = null;
  }
};

const handleDismiss = () => {
  isVisible.value = false;
  clearDismissTimer();
  emit('dismiss');
};

watch(() => message.value, (newMessage) => {
  if (newMessage) {
    isVisible.value = true;
    clearDismissTimer();
    startDismissTimer();
  }
});

// Pre-load the status while form is submitting
const preloadStatus = computed(() => {
  if (props.loading) {
    return {
      icon: 'mdi:loading',
      classes: 'bg-blue-50 dark:bg-blue-900',
      textClasses: 'text-blue-700 dark:text-blue-100',
      iconClasses: 'text-blue-500 dark:text-blue-300 animate-spin'
    };
  }
  return currentStatus.value;
});

// Show immediately when loading starts
watch(() => props.loading, (isLoading) => {
  if (isLoading) {
    clearDismissTimer();
    isVisible.value = true;
  }
});

// Only start dismiss timer after loading finishes
watch([() => props.success, () => props.error], ([newSuccess, newError]) => {
  if (newSuccess || newError) {
    if (!props.loading) {
      startDismissTimer();
    }
  }
});

onMounted(() => {
  if (message.value) {
    isVisible.value = true;
    startDismissTimer();
  }
});

onBeforeUnmount(() => {
  clearDismissTimer();
});
</script>

<script lang="ts">
/**
 * StatusBar Component
 *
 * A floating status bar that displays form submission states, success messages, and errors.
 * Uses portal/teleport to render outside the normal DOM flow at the bottom of the viewport.
 *
 * Features:
 * - Loading, success, and error states with appropriate styling
 * - Auto-dismiss with visual progress indicator
 * - Smooth transitions between states
 * - Dark mode support
 * - Accessible aria attributes
 *
 * Portal Target:
 * Component teleports to the <body> tag by default. For custom positioning,
 * add a target element:
 * ```html
 * <div id="status-messages"></div>
 * ```
 * Then update the Teleport "to" prop accordingly:
 * ```vue
 * <StatusBar to="#status-messages" />
 * ```
 *
 * @example
 * ```vue
 * <StatusBar
 *   :success="formState.success"
 *   :error="formState.error"
 *   :loading="formState.loading"
 *   :auto-dismiss="true"
 *   :duration="5000"
 *   @dismiss="handleDismiss"
 * />
 * ```
 *
 * @prop {string} [success] - Success message to display
 * @prop {string} [error] - Error message to display
 * @prop {boolean} [loading] - Whether to show loading state
 * @prop {boolean} [autoDismiss=true] - Whether to auto-dismiss after duration
 * @prop {number} [duration=5000] - Time in ms before auto-dismiss
 * @emits {void} dismiss - Fired when status is manually dismissed or auto-dismissed
 */
</script>
