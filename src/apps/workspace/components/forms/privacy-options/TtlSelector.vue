<!-- src/apps/workspace/components/forms/privacy-options/TtlSelector.vue -->

<script setup lang="ts">
/**
 * TTL Selector
 *
 * A chip-styled dropdown for selecting secret expiration time.
 * Uses Headless UI Listbox for accessible keyboard navigation
 * and ARIA support.
 */
import OIcon from '@/shared/components/icons/OIcon.vue';
import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
import {
  Listbox,
  ListboxButton,
  ListboxLabel,
  ListboxOption,
  ListboxOptions,
} from '@headlessui/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

interface Props {
  /** Current TTL value in seconds */
  modelValue: number;
  /** Disable when form is submitting */
  disabled?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  disabled: false,
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: number): void;
}>();

const { formatDuration, lifetimeOptions } = usePrivacyOptions();

/** Find selected option object from current value */
const selectedOption = computed(() => (
    lifetimeOptions.value.find((opt) => opt.value === props.modelValue) ??
    lifetimeOptions.value[0]
  ));

/** Handle selection change from Listbox */
const handleSelect = (option: { value: number; label: string }) => {
  emit('update:modelValue', option.value);
};

/** Format display text for current selection */
const displayText = computed(() => formatDuration(props.modelValue));
</script>

<template>
  <Listbox
    :model-value="selectedOption"
    :disabled="disabled"
    @update:model-value="handleSelect">
    <div class="relative">
      <ListboxLabel class="sr-only">
        {{ t('web.secrets.selectDuration') }}
      </ListboxLabel>

      <ListboxButton
        class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium
          ring-1 ring-inset transition-all
          bg-brand-50 text-brand-700 ring-brand-600/20
          hover:bg-brand-100 hover:ring-brand-600/30
          focus:outline-none focus:ring-2 focus:ring-brand-500
          dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30
          dark:hover:bg-brand-900/50
          disabled:cursor-not-allowed disabled:opacity-50">
        <OIcon
          collection="mdi"
          name="timer-outline"
          class="size-3.5"
          aria-hidden="true" />
        <span>{{ displayText }}</span>
        <OIcon
          collection="heroicons"
          name="chevron-up-down"
          class="size-3"
          aria-hidden="true" />
      </ListboxButton>

      <transition
        leave-active-class="transition duration-100 ease-in"
        leave-from-class="opacity-100"
        leave-to-class="opacity-0">
        <ListboxOptions
          class="absolute left-0 top-full z-50 mt-1 max-h-60 w-48 overflow-auto rounded-md
            bg-white py-1 text-sm shadow-lg ring-1 ring-black/5
            focus:outline-none
            dark:bg-gray-800 dark:ring-gray-700">
          <ListboxOption
            v-for="option in lifetimeOptions"
            :key="option.value"
            v-slot="{ active, selected }"
            :value="option"
            as="template">
            <li
              :class="[
                'relative cursor-pointer select-none py-2 pl-3 pr-9',
                selected
                  ? 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300'
                  : active
                    ? 'bg-gray-100 dark:bg-gray-700'
                    : 'text-gray-700 dark:text-gray-300',
              ]">
              <span :class="[selected ? 'font-medium' : 'font-normal', 'block truncate']">
                {{ t('web.secrets.expiresIn', { duration: option.label }) }}
              </span>

              <span
                v-if="selected"
                class="absolute inset-y-0 right-0 flex items-center pr-3 text-brand-600 dark:text-brand-400">
                <OIcon
                  collection="heroicons"
                  name="check"
                  class="size-4"
                  aria-hidden="true" />
              </span>
            </li>
          </ListboxOption>
        </ListboxOptions>
      </transition>
    </div>
  </Listbox>
</template>
