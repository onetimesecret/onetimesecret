<!-- src/shared/components/ui/notifications/SubtleProgress.vue -->
<!--
  SETTINGS:
  - position: 'top' | 'bottom' (default: 'top') — store value takes precedence
  - alignment: 'left' | 'right' (default: 'right') — horizontal corner
  - showLabel: show message text (default: true) — false for icon-only pill
  - loading: show spinner state (default: false)
  - rounded: border radius (default: 'full') — 'none' | 'sm' | 'md' | 'lg' | 'xl' | 'full'

  Auto-dismiss is owned by the store. Pass `duration` to `notifications.show()`
  (default DEFAULT_AUTO_HIDE_MS in notificationsStore); use 0 to disable dismiss.

  STYLING (in getStatusConfig):
  - ringClasses: ring color/opacity per severity, e.g. 'ring-green-300/50'
    To adjust brightness: change the /50 opacity or color shade (300 → 200)
  - Pulse shadow: in @keyframes subtle-pulse, adjust rgb(0 0 0 / 0.06) opacity

  Minimal pill indicator with subtle pulse. Interchangeable with StatusBar, StatusCorner.
  Pulse animation respects prefers-reduced-motion.
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import type { NotificationAlignment } from '@/types/ui/notifications';
import { computed } from 'vue';

const { t, te } = useI18n();

type RoundedSize = 'none' | 'sm' | 'md' | 'lg' | 'xl' | 'full';

interface Props {
  loading?: boolean;
  position?: 'top' | 'bottom';
  alignment?: Exclude<NotificationAlignment, 'center'>;
  showLabel?: boolean;
  rounded?: RoundedSize;
}

const props = withDefaults(defineProps<Props>(), {
  loading: false,
  position: undefined,
  alignment: 'right',
  showLabel: true,
  rounded: 'md',
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
    return '-translate-x-2 opacity-0 scale-95';
  }
  return 'translate-x-2 opacity-0 scale-95';
});

const getStatusConfig = (type: string | null) =>
  ({
    success: {
      icon: 'check-circle',
      bgClasses: 'bg-green-50/95 dark:bg-green-950/95',
      textClasses: 'text-green-700 dark:text-green-100',
      iconClasses: 'text-green-600 dark:text-green-300',
      ringClasses: 'ring-green-300/50 dark:ring-green-700/50',
      pulse: true,
    },
    error: {
      icon: 'alert-circle',
      bgClasses: 'bg-brand-50/95 dark:bg-brand-950/95',
      textClasses: 'text-brand-700 dark:text-brand-100',
      iconClasses: 'text-brand-600 dark:text-brand-300',
      ringClasses: 'ring-brand-300/50 dark:ring-brand-700/50',
      pulse: false,
    },
    warning: {
      icon: 'alert',
      bgClasses: 'bg-branddim-50/95 dark:bg-branddim-950/95',
      textClasses: 'text-branddim-700 dark:text-branddim-100',
      iconClasses: 'text-branddim-600 dark:text-branddim-300',
      ringClasses: 'ring-branddim-300/50 dark:ring-branddim-700/50',
      pulse: false,
    },
    info: {
      icon: 'information',
      bgClasses: 'bg-brandcomp-50/95 dark:bg-brandcomp-950/95',
      textClasses: 'text-brandcomp-700 dark:text-brandcomp-100',
      iconClasses: 'text-brandcomp-600 dark:text-brandcomp-300',
      ringClasses: 'ring-brandcomp-300/50 dark:ring-brandcomp-700/50',
      pulse: true,
    },
    loading: {
      icon: 'loading',
      bgClasses: 'bg-brandcompdim-50/95 dark:bg-brandcompdim-950/95',
      textClasses: 'text-brandcompdim-700 dark:text-brandcompdim-100',
      iconClasses: 'text-brandcompdim-600 dark:text-brandcompdim-300 animate-spin',
      ringClasses: 'ring-brandcompdim-300/50 dark:ring-brandcompdim-700/50',
      pulse: false,
    },
  })[type || 'info'];

const statusConfig = computed(() => {
  if (props.loading) {
    return getStatusConfig('loading');
  }
  return getStatusConfig(notifications.severity);
});

const shouldPulse = computed(() => statusConfig.value?.pulse && !props.loading);

// Static class map so Tailwind's scanner sees literal class names.
// Dynamic `rounded-${rounded}` would be missed at build time (Tailwind v4).
const ROUNDED_CLASSES: Record<RoundedSize, string> = {
  none: 'rounded-none',
  sm: 'rounded-sm',
  md: 'rounded-md',
  lg: 'rounded-lg',
  xl: 'rounded-xl',
  full: 'rounded-full',
};
const roundedClass = computed(() => ROUNDED_CLASSES[props.rounded]);
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transform ease-out duration-200 transition"
      :enter-from-class="enterFromClasses"
      enter-to-class="translate-x-0 opacity-100 scale-100"
      leave-active-class="transition ease-in duration-150"
      leave-from-class="opacity-100 scale-100"
      :leave-to-class="enterFromClasses">
      <div
        v-if="notifications.isVisible"
        class="fixed z-50 flex items-center gap-2 px-3 py-1.5 shadow-md ring-1 backdrop-blur-sm transition-all duration-200"
        :class="[
          positionClasses,
          statusConfig?.bgClasses,
          statusConfig?.ringClasses,
          roundedClass,
          { 'animate-subtle-pulse': shouldPulse },
          { 'px-2': !showLabel }
        ]"
        role="status"
        aria-live="polite">
        <OIcon
          collection="mdi"
          :name="statusConfig?.icon || 'information'"
          class="size-4 shrink-0 transition-all duration-200"
          :class="statusConfig?.iconClasses"
          aria-hidden="true" />

        <span
          v-if="showLabel && translatedMessage"
          class="max-w-sm break-words text-sm font-medium transition-all duration-200"
          :class="statusConfig?.textClasses">
          {{ translatedMessage }}
        </span>

        <span
          v-else
          class="sr-only">
          {{ translatedMessage }}
        </span>
      </div>
    </Transition>
  </Teleport>
</template>

<style>
@keyframes subtle-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgb(0 0 0 / 0);
  }
  50% {
    box-shadow: 0 0 0 3px rgb(0 0 0 / 0.06);
  }
}

@keyframes subtle-pulse-dark {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgb(255 255 255 / 0);
  }
  50% {
    box-shadow: 0 0 0 3px rgb(255 255 255 / 0.08);
  }
}

.animate-subtle-pulse {
  animation: subtle-pulse 1.5s ease-in-out 1;
}

:root.dark .animate-subtle-pulse {
  animation-name: subtle-pulse-dark;
}

@media (prefers-reduced-motion: reduce) {
  .animate-subtle-pulse {
    animation: none;
  }
}
</style>
