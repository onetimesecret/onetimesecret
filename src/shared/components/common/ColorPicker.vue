<!-- src/shared/components/common/ColorPicker.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { computed, ref, watch, onMounted, onUnmounted } from 'vue';
import {
  ChromePicker,
  SketchPicker,
  CompactPicker,
  MaterialPicker,
  tinycolor
} from 'vue-color';
import 'vue-color/style.css';

import HoverTooltip from './HoverTooltip.vue';

const { t } = useI18n();

export type ColorPickerVariant = 'chrome' | 'sketch' | 'compact' | 'material';

const props = withDefaults(defineProps<{
  modelValue?: string;
  name: string;
  label: string;
  id?: string;
  variant?: ColorPickerVariant;
  disableAlpha?: boolean;
  presetColors?: string[];
}>(), {
  modelValue: '#dc4a22',
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

// Internal color state - vue-color preserves format, so hex in = hex out
const internalColor = ref(props.modelValue);

// Sync from parent
watch(() => props.modelValue, (newVal) => {
  if (newVal !== internalColor.value) {
    internalColor.value = newVal;
  }
});

// Emit changes to parent when internal color changes (from picker interaction)
watch(internalColor, (newVal) => {
  if (typeof newVal === 'string') {
    emit('update:modelValue', newVal.toUpperCase());
  }
});

const updateFromHexInput = (event: Event) => {
  const target = event.target as HTMLInputElement;
  let newColor = `#${target.value}`.toUpperCase();

  // Validate hex color (6 or 8 characters for alpha)
  if (/^#[0-9A-F]{6}([0-9A-F]{2})?$/i.test(newColor)) {
    internalColor.value = newColor;
    emit('update:modelValue', newColor);
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

// Close picker
const closePicker = () => {
  isOpen.value = false;
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
});

const togglePicker = () => {
  isOpen.value = !isOpen.value;
};

const pickerComponent = computed(() => {
  switch (props.variant) {
    case 'sketch': return SketchPicker;
    case 'compact': return CompactPicker;
    case 'material': return MaterialPicker;
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
      role="button"
      tabindex="0"
      :aria-expanded="isOpen"
      :aria-haspopup="true"
      :aria-label="label"
      class="group flex h-11 cursor-pointer items-center gap-3 rounded-lg border border-gray-200 bg-white px-3 shadow-sm transition-all duration-200 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:focus-within:ring-brand-400 dark:focus-within:ring-offset-0"
      @click="togglePicker"
      @keydown.enter.prevent="togglePicker"
      @keydown.space.prevent="togglePicker">
      <!-- Color Preview Circle -->
      <div class="relative flex items-center">
        <div
          class="size-6 rounded-full border-2 border-white shadow-sm ring-1 ring-gray-200 dark:border-gray-700 dark:ring-gray-600"
          role="presentation"
          :style="{ backgroundColor: previewColor }">
        </div>
      </div>

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
          @input="updateFromHexInput"
          @click.stop
          @keydown.enter.stop
          @keydown.space.stop />
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
            top: `${(triggerRef?.getBoundingClientRect().bottom ?? 0) + 8}px`,
            left: `${triggerRef?.getBoundingClientRect().left ?? 0}px`
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
.vc-compact,
.vc-material {
  font-family: inherit;
}

.dark .vc-chrome,
.dark .vc-sketch,
.dark .vc-material {
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
