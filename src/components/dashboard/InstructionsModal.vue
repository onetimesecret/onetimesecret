<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useEventListener } from '@vueuse/core';
  import { ref, watch, nextTick, onMounted, onUnmounted } from 'vue';
  import { useI18n, Composer } from 'vue-i18n';

  import HoverTooltip from '../common/HoverTooltip.vue';

  const { t } = useI18n();

  /**
   * Interface for instruction field configuration
   */
  interface InstructionField {
    key: string;
    label: string;
    tooltipContent: string;
    placeholderKey: string;
    value: string;
  }

  const props = defineProps<{
    previewI18n: Composer;
    instructionFields: InstructionField[];
    maxLength?: number;
  }>();

  const emit = defineEmits<{
    (e: 'update', key: string, value: string): void;
    (e: 'save'): void;
  }>();

  const isOpen = ref(false);
  const tooltipShown = ref<Record<string, boolean>>({});
  const activeFieldRef = ref<string | null>(null);
  const textareaRefs = ref<Record<string, HTMLTextAreaElement | null>>({});

  // Setup tooltip show/hide for each field
  const showTooltip = (key: string) => {
    tooltipShown.value = { ...tooltipShown.value, [key]: true };
  };

  const hideTooltip = (key: string) => {
    tooltipShown.value = { ...tooltipShown.value, [key]: false };
  };

  const characterCount = (value: string) => value?.length ?? 0;

  const getPlaceholderExample = (placeholderKey: string) => {
    return `${props.previewI18n.t('e-g-example')} ${placeholderKey}`;
  };

  const updateValue = (key: string, event: Event) => {
    const target = event.target as HTMLTextAreaElement;
    emit('update', key, target.value);
  };

  const toggleOpen = () => {
    isOpen.value = !isOpen.value;
  };

  const close = () => {
    isOpen.value = false;
  };

  // Handle ESC key press globally
  const handleEscPress = (e: KeyboardEvent) => {
    if (e.key === 'Escape' && isOpen.value) {
      close();
    }
  };

  const handleKeydown = (e: KeyboardEvent, key: string) => {
    // Update active field reference
    activeFieldRef.value = key;

    // Close on escape
    if (e.key === 'Escape') {
      close();
      return;
    }

    // Save on Cmd+Enter (Mac) or Ctrl+Enter (Windows)
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      emit('save');
      close();
    }
  };

  onMounted(() => {
    document.addEventListener('keydown', handleEscPress);
  });

  onUnmounted(() => {
    document.removeEventListener('keydown', handleEscPress);
  });

  // Close on click outside
  useEventListener(
    document,
    'click',
    (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const modalEl = document.querySelector('#instructions-modal');
      if (modalEl && !modalEl.contains(target) && isOpen.value) {
        close();
      }
    },
    { capture: true }
  );

  // Focus first textarea when opening
  watch(isOpen, (newValue) => {
    if (newValue && props.instructionFields.length > 0) {
      const firstKey = props.instructionFields[0].key;
      nextTick(() => {
        textareaRefs.value[firstKey]?.focus();
      });
    }
  });
</script>

<template>
  <div class="group relative">
    <HoverTooltip>{{ t('instructions') }}</HoverTooltip>
    <!-- prettier-ignore-attribute class -->
    <button
      type="button"
      @click="toggleOpen"
      class="group relative inline-flex h-11 items-center gap-2 rounded-lg
        bg-white px-4 shadow-sm ring-1 ring-gray-200 transition-all duration-200
        hover:bg-gray-50
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        dark:bg-gray-800 dark:ring-gray-700 dark:hover:bg-gray-700 dark:focus:ring-brand-400 dark:focus:ring-offset-0"
      :aria-expanded="isOpen"
      :aria-label="t('instructions')"
      aria-haspopup="true">
      <OIcon
        collection="mdi"
        name="text-box-edit"
        class="size-5"
        aria-hidden="true"
      />

      <OIcon
        collection="mdi"
        :name="isOpen ? 'chevron-up' : 'chevron-down'"
        class="size-5"
        aria-hidden="true"
      />
    </button>

    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="transform scale-95 opacity-0"
      enter-to-class="transform scale-100 opacity-100"
      leave-active-class="transition duration-75 ease-in"
      leave-from-class="transform scale-100 opacity-100"
      leave-to-class="transform scale-95 opacity-0">
      <!-- prettier-ignore-attribute class -->
      <div
        v-if="isOpen"
        id="instructions-modal"
        class="absolute right-0 z-50 mt-2 w-96 rounded-lg
          bg-white shadow-lg ring-1 ring-black/5
          dark:bg-gray-800">
        <div class="max-h-[80vh] overflow-y-auto">
          <div
            v-for="(field, index) in instructionFields"
            :key="field.key"
            class="p-4"
            :class="{ 'border-t border-gray-200 dark:border-gray-700': index > 0 }">
            <label class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-200">
              {{ field.label }}
              <OIcon
                collection="mdi"
                name="help-circle"
                class="ml-1 inline-block size-4 text-gray-400"
                @mouseenter="showTooltip(field.key)"
                @mouseleave="hideTooltip(field.key)" />
              <!-- prettier-ignore-attribute class -->
              <div
                v-if="tooltipShown[field.key]"
                class="absolute z-50 max-w-xs rounded
                  bg-gray-900 px-2 py-1 text-xs text-white shadow-lg
                  dark:bg-gray-700">
                {{ field.tooltipContent }}
              </div>
            </label>
            <!-- prettier-ignore-attribute class -->
            <textarea
              :value="field.value"
              @input="(e) => updateValue(field.key, e)"
              @keydown="(e) => handleKeydown(e, field.key)"
              :ref="(el) => { if (el) textareaRefs[field.key] = el as HTMLTextAreaElement }"
              rows="3"
              class="w-full rounded-lg border-0 text-sm shadow-sm
                outline-none ring-1 ring-gray-200 transition-all duration-200
                focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                dark:bg-gray-700 dark:text-white dark:ring-gray-700 dark:focus:ring-brand-400 dark:focus:ring-offset-0"
              :placeholder="getPlaceholderExample(field.placeholderKey)"
              @keydown.esc="close"></textarea>

            <!-- prettier-ignore-attribute class -->
            <div
              class="mt-2 flex items-center justify-between text-xs text-gray-500 dark:text-gray-400">
              <span>{{ $t('charactercount-500-characters', [characterCount(field.value)]) }}</span>
              <span v-if="index === instructionFields.length - 1">{{ $t('press-esc-to-close') }}</span>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>
