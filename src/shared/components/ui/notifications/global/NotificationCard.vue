<!-- src/shared/components/ui/notifications/global/NotificationCard.vue -->
<!--
  Corner card (max-w-sm) with dismiss button and countdown progress bar.
  Slides in from the horizontal edge.

  Previously: StatusCorner.vue
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { getSeverityMeta, getStandardColors } from '../severityConfig';
import { computed } from 'vue';

interface Props {
  message: string;
  severity: string | null;
  show?: boolean;
  loading?: boolean;
  position?: 'top' | 'bottom';
  alignment?: 'left' | 'right';
  dismissible?: boolean;
  duration?: number;
}

const props = withDefaults(defineProps<Props>(), {
  show: false,
  loading: false,
  position: 'top',
  alignment: 'right',
  dismissible: true,
  duration: 5000,
});

const emit = defineEmits<{ dismiss: [] }>();

const effectiveSeverity = computed(() => props.loading ? 'loading' : props.severity);
const meta = computed(() => getSeverityMeta(effectiveSeverity.value));
const colorConfig = computed(() => getStandardColors(effectiveSeverity.value));

const positionClasses = computed(() => {
  const vertical = props.position === 'top' ? 'top-4' : 'bottom-4';
  const horizontal = props.alignment === 'left' ? 'left-4' : 'right-4';
  return `${vertical} ${horizontal}`;
});

const enterFromClasses = computed(() =>
  props.alignment === 'left'
    ? '-translate-x-full opacity-0'
    : 'translate-x-full opacity-0'
);

const iconClasses = computed(() => {
  const base = colorConfig.value.iconClasses;
  return meta.value.spinIcon ? `${base} animate-spin motion-reduce:animate-none` : base;
});

const showProgressBar = computed(() =>
  props.dismissible && !props.loading && props.severity
);
</script>

<template>
  <Transition
    enter-active-class="transform ease-out duration-300 transition"
    :enter-from-class="enterFromClasses"
    enter-to-class="translate-x-0 opacity-100"
    leave-active-class="transition ease-in duration-200"
    leave-from-class="opacity-100 translate-x-0"
    :leave-to-class="enterFromClasses">
    <div
      v-if="show"
      class="fixed z-50 flex max-w-sm items-center gap-3 rounded-lg px-4 py-3 shadow-lg ring-1 backdrop-blur-sm transition-colors duration-200"
      :class="[positionClasses, colorConfig.bgClasses, colorConfig.ringClasses]"
      role="status"
      aria-live="polite">
      <OIcon
        collection="mdi"
        :name="meta.icon"
        class="size-5 shrink-0 transition-all duration-200"
        :class="iconClasses"
        aria-hidden="true" />

      <span
        class="min-w-0 flex-1 text-sm font-medium transition-all duration-200"
        :class="colorConfig.textClasses">
        {{ message }}
      </span>

      <button
        v-if="dismissible && !loading"
        type="button"
        class="shrink-0 rounded-full p-0.5 transition-colors hover:bg-black/5 dark:hover:bg-white/10"
        :class="colorConfig.textClasses"
        @click="emit('dismiss')">
        <span class="sr-only">Dismiss</span>
        <OIcon
          collection="mdi"
          name="close"
          class="size-4" />
      </button>

      <div
        v-if="showProgressBar"
        class="progress-shrink absolute bottom-0 left-0 h-0.5 rounded-full bg-current opacity-30"
        :class="colorConfig.textClasses"
        :style="{ animationDuration: `${duration}ms` }">
      </div>
    </div>
  </Transition>
</template>

<style>
@keyframes shrink {
  from { width: 100%; }
  to { width: 0%; }
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
