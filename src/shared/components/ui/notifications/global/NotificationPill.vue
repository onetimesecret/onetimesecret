<!-- src/shared/components/ui/notifications/global/NotificationPill.vue -->
<!--
  Small rounded pill in a viewport corner. Icon + optional label with
  subtle pulse on success/info. No dismiss button — auto-dismiss only.

  Previously: SubtleProgress.vue
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { getSeverityMeta, getInvertedColors } from '../severityConfig';
import { computed } from 'vue';

type RoundedSize = 'none' | 'sm' | 'md' | 'lg' | 'xl' | 'full';

interface Props {
  message: string;
  severity: string | null;
  show?: boolean;
  loading?: boolean;
  position?: 'top' | 'bottom';
  alignment?: 'left' | 'right';
  showLabel?: boolean;
  rounded?: RoundedSize;
}

const props = withDefaults(defineProps<Props>(), {
  show: false,
  loading: false,
  position: 'top',
  alignment: 'right',
  showLabel: true,
  rounded: 'md',
});

const effectiveSeverity = computed(() => props.loading ? 'loading' : props.severity);
const meta = computed(() => getSeverityMeta(effectiveSeverity.value));
const colorConfig = computed(() => getInvertedColors(effectiveSeverity.value));

const positionClasses = computed(() => {
  const vertical = props.position === 'top' ? 'top-4' : 'bottom-4';
  const horizontal = props.alignment === 'left' ? 'left-4' : 'right-4';
  return `${vertical} ${horizontal}`;
});

const enterFromClasses = computed(() =>
  props.alignment === 'left'
    ? '-translate-x-2 opacity-0 scale-95'
    : 'translate-x-2 opacity-0 scale-95'
);

const shouldPulse = computed(() => meta.value.pulse && !props.loading);

const ROUNDED_CLASSES: Record<RoundedSize, string> = {
  none: 'rounded-none',
  sm: 'rounded-sm',
  md: 'rounded-md',
  lg: 'rounded-lg',
  xl: 'rounded-xl',
  full: 'rounded-full',
};
const roundedClass = computed(() => ROUNDED_CLASSES[props.rounded]);

const iconClasses = computed(() => {
  const base = colorConfig.value.iconClasses;
  return meta.value.spinIcon ? `${base} animate-spin motion-reduce:animate-none` : base;
});
</script>

<template>
  <Transition
    enter-active-class="transform ease-out duration-200 transition"
    :enter-from-class="enterFromClasses"
    enter-to-class="translate-x-0 opacity-100 scale-100"
    leave-active-class="transition ease-in duration-150"
    leave-from-class="opacity-100 scale-100"
    :leave-to-class="enterFromClasses">
    <div
      v-if="show"
      class="fixed z-50 flex items-center gap-2 px-3 py-1.5 shadow-md ring-1 backdrop-blur-sm transition-all duration-200"
      :class="[
        positionClasses,
        colorConfig.bgClasses,
        colorConfig.ringClasses,
        roundedClass,
        { 'animate-subtle-pulse': shouldPulse },
        { 'px-2': !showLabel }
      ]"
      role="status"
      aria-live="polite">
      <OIcon
        collection="mdi"
        :name="meta.icon"
        class="size-4 shrink-0 transition-all duration-200"
        :class="iconClasses"
        aria-hidden="true" />

      <span
        v-if="showLabel && message"
        class="max-w-sm break-words text-sm font-medium transition-all duration-200"
        :class="colorConfig.textClasses">
        {{ message }}
      </span>

      <span
        v-else
        class="sr-only">
        {{ message }}
      </span>
    </div>
  </Transition>
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
