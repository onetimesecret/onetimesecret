<!-- src/shared/components/ui/notifications/StatusBar.vue -->
<!--
  SETTINGS:
  - position: 'top' | 'bottom' (default: 'bottom') — store value takes precedence
  - duration: ms for progress bar animation (default: 4000)
  - autoDismiss: show progress bar (default: true) — actual timeout is store's 5000ms
  - loading: show spinner state (default: false)

  Full-width banner. Interchangeable with StatusCorner, SubtleProgress.
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { computed } from 'vue';

const { t, te } = useI18n();

interface Props {
  autoDismiss?: boolean;
  duration?: number;
  loading?: boolean;
  position?: 'top' | 'bottom';
}

const props = withDefaults(defineProps<Props>(), {
  autoDismiss: true,
  duration: 2000,
  loading: false,
  position: 'bottom'
});

const notifications = useNotificationsStore();

const effectivePosition = computed(() =>
  notifications.position || props.position
);

const translatedMessage = computed(() =>
  te(notifications.message) ? t(notifications.message) : notifications.message);

const getStatusConfig = (type: string | null) => ({
  success: {
    icon: 'check-circle',
    classes: 'bg-green-50/90 dark:bg-green-950/90',
    textClasses: 'text-green-700 dark:text-green-100',
    iconClasses: 'text-green-600 dark:text-green-300'
  },
  error: {
    icon: 'alert-circle',
    classes: 'bg-brand-50/90 dark:bg-brand-950/90',
    textClasses: 'text-brand-700 dark:text-brand-100',
    iconClasses: 'text-brand-600 dark:text-brand-300'
  },
  warning: {
    icon: 'alert',
    classes: 'bg-branddim-50/90 dark:bg-branddim-950/90',
    textClasses: 'text-branddim-700 dark:text-branddim-100',
    iconClasses: 'text-branddim-600 dark:text-branddim-300'
  },
  info: {
    icon: 'information',
    classes: 'bg-brandcomp-50/90 dark:bg-brandcomp-950/90',
    textClasses: 'text-brandcomp-700 dark:text-brandcomp-100',
    iconClasses: 'text-brandcomp-600 dark:text-brandcomp-300'
  },
  loading: {
    icon: 'loading',
    classes: 'bg-brandcompdim-50/90 dark:bg-brandcompdim-950/90',
    textClasses: 'text-brandcompdim-700 dark:text-brandcompdim-100',
    iconClasses: 'text-brandcompdim-600 dark:text-brandcompdim-300 animate-spin'
  },
})[type || 'info'];

const statusConfig = computed(() => {
  if (props.loading) {
    return getStatusConfig('loading');
  }
  return getStatusConfig(notifications.severity);
});
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
        class="fixed inset-x-0 z-50 flex items-center justify-between px-4 py-3 shadow-lg transition-colors duration-200"
        :class="[
          statusConfig?.classes,
          effectivePosition === 'top' ? 'top-0' : 'bottom-0'
        ]"
        role="status"
        aria-live="polite">
        <div class="flex min-w-0 flex-1 items-center space-x-3">
          <OIcon
            collection="mdi"
            :name="statusConfig?.icon || 'information'"
            class="size-5 shrink-0 transition-all duration-200"
            :class="statusConfig?.iconClasses"
            aria-hidden="true" />
          <span
            class="text-sm font-medium break-words transition-all duration-200"
            :class="statusConfig?.textClasses">
            {{ translatedMessage }}
          </span>
        </div>

        <div class="flex items-center">
          <button
            v-if="!loading"
            type="button"
            class="ml-4 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
            @click="notifications.hide">
            <span class="sr-only">{{ t('web.LABELS.dismiss') }}</span>
            <OIcon
              collection="mdi"
              name="close"
              class="size-5" />
          </button>
        </div>

        <!-- Progress indicator -->
        <div
          v-if="autoDismiss && !loading && notifications.severity"
          class="progress-shrink absolute left-0 h-1 bg-current opacity-30"
          :class="[
            (effectivePosition === 'top' ? 'bottom-0' : 'top-0'),
            statusConfig?.textClasses
          ]"
          :style="{ animationDuration: `${duration}ms` }">
        </div>
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

.progress-shrink {
  animation: shrink linear forwards;
}

@media (prefers-reduced-motion: reduce) {
  .progress-shrink {
    animation: none;
    width: 100%;
  }
}
</style>
