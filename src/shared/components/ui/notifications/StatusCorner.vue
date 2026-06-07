<!-- src/shared/components/ui/notifications/StatusCorner.vue -->
<!--
  SETTINGS:
  - position: 'top' | 'bottom' (default: 'top') — store value takes precedence
  - alignment: 'left' | 'right' (default: 'right') — horizontal corner
  - duration: ms for progress bar animation (default: 4000)
  - autoDismiss: show progress bar (default: true) — actual timeout is store's 5000ms
  - loading: show spinner state (default: false)

  Compact corner toast. Interchangeable with StatusBar, SubtleProgress.
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import type { NotificationAlignment } from '@/types/ui/notifications';
import { computed } from 'vue';

const { t, te } = useI18n();

interface Props {
  autoDismiss?: boolean;
  duration?: number;
  loading?: boolean;
  position?: 'top' | 'bottom';
  alignment?: Exclude<NotificationAlignment, 'center'>;
}

const props = withDefaults(defineProps<Props>(), {
  autoDismiss: true,
  duration: 4000,
  loading: false,
  position: undefined,
  alignment: 'right',
});

const notifications = useNotificationsStore();

const effectivePosition = computed(() =>
  notifications.position || props.position || 'top'
);

const translatedMessage = computed(() =>
  te(notifications.message) ? t(notifications.message) : notifications.message
);

const positionClasses = computed(() => {
  const vertical = effectivePosition.value === 'top' ? 'top-4' : 'bottom-4';
  const horizontal = props.alignment === 'left' ? 'left-4' : 'right-4';
  return `${vertical} ${horizontal}`;
});

const enterFromClasses = computed(() => {
  if (props.alignment === 'left') {
    return '-translate-x-full opacity-0';
  }
  return 'translate-x-full opacity-0';
});

const getStatusConfig = (type: string | null) =>
  ({
    success: {
      icon: 'check-circle',
      bgClasses: 'bg-green-50/95 dark:bg-green-950/95',
      textClasses: 'text-green-700 dark:text-green-100',
      iconClasses: 'text-green-600 dark:text-green-300',
      ringClasses: 'ring-green-200/50 dark:ring-green-800/50',
    },
    error: {
      icon: 'alert-circle',
      bgClasses: 'bg-brand-50/95 dark:bg-brand-950/95',
      textClasses: 'text-brand-700 dark:text-brand-100',
      iconClasses: 'text-brand-600 dark:text-brand-300',
      ringClasses: 'ring-brand-200/50 dark:ring-brand-800/50',
    },
    warning: {
      icon: 'alert',
      bgClasses: 'bg-branddim-50/95 dark:bg-branddim-950/95',
      textClasses: 'text-branddim-700 dark:text-branddim-100',
      iconClasses: 'text-branddim-600 dark:text-branddim-300',
      ringClasses: 'ring-branddim-200/50 dark:ring-branddim-800/50',
    },
    info: {
      icon: 'information',
      bgClasses: 'bg-brandcomp-50/95 dark:bg-brandcomp-950/95',
      textClasses: 'text-brandcomp-700 dark:text-brandcomp-100',
      iconClasses: 'text-brandcomp-600 dark:text-brandcomp-300',
      ringClasses: 'ring-brandcomp-200/50 dark:ring-brandcomp-800/50',
    },
    loading: {
      icon: 'loading',
      bgClasses: 'bg-brandcompdim-50/95 dark:bg-brandcompdim-950/95',
      textClasses: 'text-brandcompdim-700 dark:text-brandcompdim-100',
      iconClasses: 'text-brandcompdim-600 dark:text-brandcompdim-300 animate-spin motion-reduce:animate-none',
      ringClasses: 'ring-brandcompdim-200/50 dark:ring-brandcompdim-800/50',
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
      :enter-from-class="enterFromClasses"
      enter-to-class="translate-x-0 opacity-100"
      leave-active-class="transition ease-in duration-200"
      leave-from-class="opacity-100 translate-x-0"
      :leave-to-class="enterFromClasses">
      <div
        v-if="notifications.isVisible"
        class="fixed z-50 flex max-w-sm items-center gap-3 rounded-lg px-4 py-3 shadow-lg ring-1 backdrop-blur-sm transition-colors duration-200"
        :class="[positionClasses, statusConfig?.bgClasses, statusConfig?.ringClasses]"
        role="status"
        aria-live="polite">
        <OIcon
          collection="mdi"
          :name="statusConfig?.icon || 'information'"
          class="size-5 shrink-0 transition-all duration-200"
          :class="statusConfig?.iconClasses"
          aria-hidden="true" />

        <span
          class="min-w-0 flex-1 text-sm font-medium transition-all duration-200"
          :class="statusConfig?.textClasses">
          {{ translatedMessage }}
        </span>

        <button
          v-if="!loading"
          type="button"
          class="shrink-0 rounded-full p-0.5 transition-colors hover:bg-black/5 dark:hover:bg-white/10"
          :class="statusConfig?.textClasses"
          @click="notifications.hide">
          <span class="sr-only">{{ t('web.LABELS.dismiss') }}</span>
          <OIcon
            collection="mdi"
            name="close"
            class="size-4" />
        </button>

        <!-- Progress indicator -->
        <div
          v-if="autoDismiss && !loading && notifications.severity"
          class="progress-shrink absolute bottom-0 left-0 h-0.5 rounded-full bg-current opacity-30"
          :class="statusConfig?.textClasses"
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
