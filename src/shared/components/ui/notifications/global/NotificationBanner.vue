<!-- src/shared/components/ui/notifications/global/NotificationBanner.vue -->
<!--
  Full-width banner pinned to the top or bottom edge of the viewport.
  Dismiss button and countdown progress bar.

  Previously: StatusBar.vue
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { getSeverityMeta, getBannerColors } from '../severityConfig';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

interface Props {
  message: string;
  severity: string | null;
  show?: boolean;
  loading?: boolean;
  position?: 'top' | 'bottom';
  dismissible?: boolean;
  duration?: number;
}

const props = withDefaults(defineProps<Props>(), {
  show: false,
  loading: false,
  position: 'bottom',
  dismissible: true,
  duration: 5000,
});

const emit = defineEmits<{ dismiss: [] }>();

const { t } = useI18n();

const effectiveSeverity = computed(() => props.loading ? 'loading' : props.severity);
const meta = computed(() => getSeverityMeta(effectiveSeverity.value));
const colorConfig = computed(() => getBannerColors(effectiveSeverity.value));

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
    :enter-from-class="position === 'top'
      ? '-translate-y-2 opacity-0 sm:-translate-y-0 sm:translate-x-2'
      : 'translate-y-2 opacity-0 sm:translate-y-0 sm:translate-x-2'"
    enter-to-class="translate-y-0 opacity-100 sm:translate-x-0"
    leave-active-class="transition ease-in duration-100"
    leave-from-class="opacity-100"
    leave-to-class="opacity-0">
    <div
      v-if="show"
      class="fixed inset-x-0 z-50 flex items-center justify-between px-4 py-3 shadow-lg transition-colors duration-200"
      :class="[
        colorConfig.bgClasses,
        position === 'top' ? 'top-0' : 'bottom-0'
      ]"
      role="status"
      aria-live="polite">
      <div class="flex min-w-0 flex-1 items-center space-x-3">
        <OIcon
          collection="mdi"
          :name="meta.icon"
          class="size-5 shrink-0 transition-all duration-200"
          :class="iconClasses"
          aria-hidden="true" />
        <span
          class="text-sm font-medium break-words transition-all duration-200"
          :class="colorConfig.textClasses">
          {{ message }}
        </span>
      </div>

      <div class="flex items-center">
        <button
          v-if="dismissible && !loading"
          type="button"
          class="ml-4 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
          @click="emit('dismiss')">
          <span class="sr-only">{{ t('web.LABELS.dismiss') }}</span>
          <OIcon
            collection="mdi"
            name="close"
            class="size-5" />
        </button>
      </div>

      <div
        v-if="showProgressBar"
        class="progress-shrink absolute left-0 h-1 bg-current opacity-30"
        :class="[
          (position === 'top' ? 'bottom-0' : 'top-0'),
          colorConfig.textClasses
        ]"
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
