<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(defineProps<{
  modelValue?: string;
  name: string;
  label: string;
  id?: string;
}>(), {
  modelValue: '#dc4a22', // Provide default color
  id: undefined
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

// Provide default props
const label = computed(() => props.label || 'Color Picker');
const id = computed(() => props.id || 'color-picker');
const name = computed(() => props.name || 'color');
const currentColor = computed(() => props.modelValue || '#dc4a22');

const updateColor = (event: Event, isText = false) => {
  const target = event.target as HTMLInputElement;
  let newColor = target.value;

  if (isText) {
    // Handle text input (without #)
    newColor = `#${newColor}`.toUpperCase();
  } else {
    // Handle color picker input (with #)
    newColor = newColor.toUpperCase();
  }

  // Validate hex color
  if (/^#[0-9A-F]{6}$/i.test(newColor)) {
    emit('update:modelValue', newColor);
  }
};

</script>

<template>
  <div class="relative">
    <label
      :id="id + '-label'"
      class="sr-only">{{ label }}</label>
    <div
      class="group
            flex h-11 items-center
            gap-3 rounded-lg
            border
            border-gray-200 bg-white
            px-3
            shadow-sm
            dark:border-gray-600
            dark:bg-gray-800">
      <!-- Color Preview Circle -->
      <div class="relative flex items-center">
        <div
          class="size-6 rounded-full border-2 border-white shadow-sm ring-1 ring-gray-200 dark:border-gray-700 dark:ring-gray-600"
          role="presentation"
          :style="{ backgroundColor: modelValue }">
          <input
            type="color"
            :name="name"
            :value="currentColor"
            @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
            class="absolute inset-0 size-full cursor-pointer opacity-0"
            :aria-labelledby="id + '-label'"
          />
        </div>
      </div>

      <!-- Hex Input -->
      <div class="relative flex items-center">
        <span
          class="absolute left-0
             text-sm font-medium
             text-gray-400
             dark:text-gray-500"
          aria-hidden="true">#</span>
        <input
          type="text"
          :value="modelValue.replace('#', '')"
          @input="(e) => updateColor(e, true)"
          :name="name"
          class="w-[5.5rem] border-none
             bg-transparent
             p-0
             pl-4
             text-sm font-medium uppercase
             text-gray-900
             placeholder:text-gray-400
             focus:ring-0
             dark:text-gray-100"
          pattern="[0-9A-Fa-f]{6}"
          placeholder="2ACFCF"
          maxlength="6"
          spellcheck="false"
          :aria-label="label"
        />
      </div>
    </div>
  </div>
</template>
