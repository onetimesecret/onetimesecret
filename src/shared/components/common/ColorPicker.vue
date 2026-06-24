<!-- src/shared/components/common/ColorPicker.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { computed, ref, watch, onMounted, onUnmounted } from 'vue';
import {
  ChromePicker,
  SketchPicker,
  CompactPicker,
  tinycolor
} from 'vue-color';
import 'vue-color/style.css';

import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import HoverTooltip from './HoverTooltip.vue';

const { t } = useI18n();

export type ColorPickerVariant = 'chrome' | 'sketch' | 'compact';

const props = withDefaults(defineProps<{
  modelValue?: string;
  name: string;
  label: string;
  id?: string;
  variant?: ColorPickerVariant;
  disableAlpha?: boolean;
  presetColors?: string[];
}>(), {
  modelValue: NEUTRAL_BRAND_DEFAULTS.primary_color,
  id: undefined,
  variant: 'chrome',
  disableAlpha: false,
  presetColors: undefined
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const label = computed(() => props.label || t('web.branding.color_picker'));
const id = computed(() => props.id || 'color-picker');

const isOpen = ref(false);
const pickerRef = ref<HTMLElement | null>(null);
const triggerRef = ref<HTMLElement | null>(null);
const popoverPosition = ref({ top: 0, left: 0 });

// vue-color emits either a hex string or `{hex, hex8, rgba, ...}`.
// Collapse both shapes to an uppercase hex string for the rest of the component.
const normalizeHex = (val: unknown): string | undefined => {
  if (typeof val === 'string') return val.toUpperCase();
  const obj = val as { hex8?: string; hex?: string } | null | undefined;
  return (obj?.hex8 ?? obj?.hex)?.toUpperCase();
};

// Internal color state — kept normalized so consumers (displayHex, previewColor,
// the picker's v-model) all see a string.
const internalColor = ref<string>(props.modelValue);

// Sync from parent
watch(() => props.modelValue, (newVal) => {
  if (newVal !== internalColor.value) {
    internalColor.value = newVal;
  }
});

// Normalize and propagate changes from the picker (which may emit objects).
watch(internalColor, (newVal) => {
  const hex = normalizeHex(newVal);
  if (!hex) return;
  // Coerce object payloads back into a string so the rest of the component
  // doesn't have to handle two shapes. Re-entry terminates: the next pass is
  // already a string and equal to itself.
  if (internalColor.value !== hex) {
    internalColor.value = hex;
  }
  if (hex !== props.modelValue?.toUpperCase()) {
    emit('update:modelValue', hex);
  }
});

const updateFromHexInput = (event: Event) => {
  const target = event.target as HTMLInputElement;
  let newColor = `#${target.value}`.toUpperCase();

  // Validate hex color (6 or 8 characters for alpha).
  // The internalColor watcher is the single emit path.
  if (/^#[0-9A-F]{6}([0-9A-F]{2})?$/i.test(newColor)) {
    internalColor.value = newColor;
  }
};

const displayHex = computed(() => {
  const color = internalColor.value || props.modelValue;
  return color.replace('#', '');
});

const previewColor = computed(() => {
  const color = internalColor.value || props.modelValue;
  const tc = tinycolor(color);
  return tc.toRgbString();
});

const updatePopoverPosition = () => {
  const rect = triggerRef.value?.getBoundingClientRect();
  if (!rect) return;
  popoverPosition.value = { top: rect.bottom + 8, left: rect.left };
};

// Close picker
const closePicker = () => {
  isOpen.value = false;
  window.removeEventListener('scroll', updatePopoverPosition, true);
  window.removeEventListener('resize', updatePopoverPosition);
};

// Escape key to close
const handleKeyDown = (event: KeyboardEvent) => {
  if (event.key === 'Escape' && isOpen.value) {
    closePicker();
    triggerRef.value?.focus();
  }
};

onMounted(() => {
  document.addEventListener('keydown', handleKeyDown);
});

onUnmounted(() => {
  document.removeEventListener('keydown', handleKeyDown);
  window.removeEventListener('scroll', updatePopoverPosition, true);
  window.removeEventListener('resize', updatePopoverPosition);
});

const togglePicker = () => {
  if (!isOpen.value) {
    updatePopoverPosition();
    window.addEventListener('scroll', updatePopoverPosition, { capture: true, passive: true });
    window.addEventListener('resize', updatePopoverPosition, { passive: true });
    isOpen.value = true;
  } else {
    closePicker();
  }
};

const pickerComponent = computed(() => {
  switch (props.variant) {
    case 'sketch': return SketchPicker;
    case 'compact': return CompactPicker;
    case 'chrome':
    default: return ChromePicker;
  }
});

// Props to pass to the picker based on variant (excluding modelValue - use v-model)
const pickerProps = computed(() => {
  const base: Record<string, unknown> = {};

  if (props.variant === 'chrome' || props.variant === 'sketch') {
    base.disableAlpha = props.disableAlpha;
  }

  if (props.variant === 'sketch' && props.presetColors) {
    base.presetColors = props.presetColors;
  }

  if (props.variant === 'compact' && props.presetColors) {
    base.palette = props.presetColors;
  }

  return base;
});
</script>

<template>
  <div class="group relative">
    <HoverTooltip>{{ label }}</HoverTooltip>
    <label
      :id="id + '-label'"
      class="sr-only">{{ label }}</label>

    <div
      ref="triggerRef"
      class="group flex h-11 items-center gap-3 rounded-lg border border-gray-200 bg-white px-3 shadow-sm transition-all duration-200 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2 dark:border-gray-600 dark:bg-gray-800 dark:focus-within:ring-brand-400 dark:focus-within:ring-offset-0">
      <!-- Color Preview Circle (acts as picker trigger) -->
      <button
        type="button"
        :aria-expanded="isOpen"
        :aria-haspopup="true"
        :aria-label="label"
        class="relative flex items-center rounded-full focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 dark:focus-visible:ring-brand-400"
        @click="togglePicker">
        <span
          class="block size-6 rounded-full border-2 border-white shadow-sm ring-1 ring-gray-200 dark:border-gray-700 dark:ring-gray-600"
          :style="{ backgroundColor: previewColor }">
        </span>
      </button>

      <!-- Hex Display -->
      <div class="relative flex items-center">
        <span
          class="text-sm font-medium text-gray-400 dark:text-gray-500"
          aria-hidden="true">#</span>
        <input
          type="text"
          :value="displayHex"
          :name="name"
          class="w-[5.5rem] border-none bg-transparent p-0 pl-1 text-sm font-medium uppercase text-gray-900 placeholder:text-gray-400 focus:ring-0 dark:text-gray-100"
          :class="{ 'w-[7rem]': displayHex.length > 6 }"
          pattern="[0-9A-Fa-f]{6,8}"
          :placeholder="disableAlpha ? '2ACFCF' : '2ACFCFFF'"
          :maxlength="disableAlpha ? 6 : 8"
          spellcheck="false"
          :aria-label="label"
          @input="updateFromHexInput" />
      </div>
    </div>

    <!-- Picker Popover -->
    <Teleport to="body">
      <!-- Backdrop for click-outside detection -->
      <div
        v-if="isOpen"
        class="fixed inset-0 z-[99]"
        @click="closePicker" ></div>

      <Transition
        enter-active-class="transition duration-100 ease-out"
        enter-from-class="opacity-0 scale-95"
        enter-to-class="opacity-100 scale-100"
        leave-active-class="transition duration-75 ease-in"
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95">
        <div
          v-if="isOpen"
          ref="pickerRef"
          class="fixed z-[100] rounded-lg shadow-xl ring-1 ring-black/5 dark:ring-white/10"
          :style="{
            top: `${popoverPosition.top}px`,
            left: `${popoverPosition.left}px`
          }">
          <component
            :is="pickerComponent"
            v-model="internalColor"
            v-bind="pickerProps" />
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style>
/* Override vue-color styles for dark mode compatibility */
.vc-chrome,
.vc-sketch,
.vc-compact {
  font-family: inherit;
}

.dark .vc-chrome,
.dark .vc-sketch {
  background: rgb(31 41 55) !important;
}

.dark .vc-chrome-body,
.dark .vc-sketch-presets {
  background: rgb(31 41 55) !important;
}

.dark .vc-input__input {
  background: rgb(55 65 81) !important;
  color: rgb(243 244 246) !important;
  border-color: rgb(75 85 99) !important;
}

.dark .vc-input__label {
  color: rgb(156 163 175) !important;
}

.dark .vc-chrome-toggle-icon path,
.dark .vc-chrome-toggle-icon-highlight {
  fill: rgb(156 163 175) !important;
}

.dark .vc-sketch-presets-label {
  color: rgb(156 163 175) !important;
}
</style>
