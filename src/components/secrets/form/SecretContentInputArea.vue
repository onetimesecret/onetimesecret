
<!--

  FEATURE: Closing dropdown on click outside or Escape key press

  1. Added `ref="dropdownRef"` to the dropdown container div.
  2. Created a `closeDropdown` function to close the dropdown.
  3. Added `handleClickOutside` function to check if a click occurred outside the dropdown.
  4. Added `handleEscapeKey` function to close the dropdown when the Escape key is pressed.
  5. Set up event listeners in the `onMounted` hook and removed them in the `onUnmounted` hook.

  These changes will make the dropdown close when clicking outside of it or pressing the
  Escape key. The click outside functionality checks if the click target is not contained
  within the dropdown element, and if so, it closes the dropdown. The Escape key
  functionality simply closes the dropdown when the key is pressed.

  TESTING:
  To test the readability and distinguishability of various characters,
  including commonly problematic ones, use the following command to generate
  a QR code. This will help validate how different characters are rendered
  and perceived in different contexts:

    $ qrencode -t UTF8i "5uP0R s3kRU7\!"

    █▀▀▀▀▀█ ▄█ █▀ █▀▀▀▀▀█
    █ ███ █ ▀█ ▄▀ █ ███ █
    █ ▀▀▀ █ █  ▄█ █ ▀▀▀ █
    ▀▀▀▀▀▀▀ █▄█▄█ ▀▀▀▀▀▀▀
    ▀█▄▀  ▀▀ ▀▀▄ ▄▀▀█ ▀▀▄
    █  █ █▀▄▄██▄▀ ▄ ▄█▀ █
    ▀ ▀ ▀ ▀▀▄▀█▄█ ▄ ▀█▀██
    █▀▀▀▀▀█ ▀▄█▀█▀▀█▀█▀
    █ ███ █ ▄▀▀██▄█▄▄▀ ▄▄
    █ ▀▀▀ █ ▄█▄ ▀▄ ▄▀ ▀ ▀
    ▀▀▀▀▀▀▀ ▀   ▀▀  ▀ ▀▀

  Here is a comprehensive string that includes a mix of problematic
  characters (such as 'o', '0', 'l', '1', 'I') and regular
  characters, numbers, and symbols:

    a0oO1lI2b3c4d5e6f7g8h9iIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ0123456789!
    @#$%^&*()_+-=[]{}|;:',.<>?/~`a0oO1lI2b3c4d5e6f7g8h9iIjJkKlLmMnNoOpPqQ
    rRsStTuUvVwWxXyYzZ0123456789!@#$%^&*()_+-=[]{}|;:',.<>?/~`a0oO1lI2b3c
    4d5e6f7g8h9iIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ0123456789!@#$%^&*()_+
    -=[]{}|;:',.<>?/~`

  Additionally, here are some leetspeak words to further test and
  validate character rendering:

    h3ll0 w0rld 1337 c0d3 pr0gr4mm3r h4ck3r s3cur1ty 3xpl01t 5up3r s3kRU7

-->

<script setup lang="ts">
/**
 * SecretContentInputArea Component
 *
 * This component provides a textarea for users to input secret content and optionally
 * select a domain from a dropdown. It handles the input of secret text, auto-resizing
 * of the textarea, and domain selection if enabled.
 *
 * Features:
 * - Auto-resizing textarea for secret content input
 * - Optional domain selection dropdown
 * - Emits events for content and domain changes
 * - Handles closing of dropdown on outside click or Escape key press
 *
 * Usage:
 * <SecretContentInputArea
 *   :availableDomains="availableDomains"
 *   :initialDomain="selectedDomain"
 *   :withDomainDropdown="domainsEnabled"
 *   @update:selectedDomain="updateSelectedDomain"
 *   @update:content="secretContent = $event"
 * />
 */

// 1. Imports
import OIcon from '@/components/icons/OIcon.vue';
import { computed, ref, onMounted, onUnmounted, watch, WatchStopHandle } from 'vue';
import { WindowService } from '@/services/window.service';

const availablePlans = WindowService.get('available_plans') ?? [];
const cust = WindowService.get('cust');

const planOptions = cust?.plan.options || availablePlans?.anonymous.options;
const maxSize = planOptions?.size || 10000; // in characters

const isHovering = ref(false);

const showCounter = computed(() => {
  return isHovering.value || charCount.value > localMaxLength.value / 2;
});

const handleMouseEnter = () => {
  isHovering.value = true;
};

const handleMouseLeave = () => {
  isHovering.value = false;
};

// New function to format numbers
const formatNumber = (num: number) => {
  return new Intl.NumberFormat().format(num);
};

// Computed property for formatted character count
const formattedCharCount = computed(() => formatNumber(charCount.value));

// Computed property for formatted max length
const formattedMaxLength = computed(() => formatNumber(localMaxLength.value));


// 2. Interface and Props
interface Props {
  availableDomains?: string[];
  initialDomain?: string;
  withDomainDropdown?: boolean;
  maxLength?: number;
  initialContent?: string;
}

const props = withDefaults(defineProps<Props>(), {
  initialDomain: '',
  withDomainDropdown: false,
});

// 3. Emits
const emit = defineEmits(['update:selected-domain', 'update:content']);

// 4. Refs
const content = ref(props.initialContent || '');
const charCount = ref(0);
const isOpen = ref(false);
const selectedDomain = ref(props.initialDomain);
const dropdownRef = ref<HTMLElement | null>(null);
const textareaRef = ref<HTMLTextAreaElement | null>(null);
const maxHeight = 400; // Maximum height in pixels
const localMaxLength = ref(props.maxLength || maxSize);
let watchStop: WatchStopHandle | null = null; // To store the watcher stop function

// 5. Methods
const toggleDropdown = (event: Event) => {
  event.stopPropagation();
  isOpen.value = !isOpen.value;
};

const selectDomain = (domain: string) => {
  selectedDomain.value = domain;
  emit('update:selected-domain', domain);
  isOpen.value = false;
};

const closeDropdown = () => {
  isOpen.value = false;
};

const handleClickOutside = (event: MouseEvent) => {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target as Node)) {
    closeDropdown();
  }
};

const handleEscapeKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeDropdown();
  }
};

const adjustTextareaHeight = () => {
  if (textareaRef.value) {
    textareaRef.value.style.height = 'auto';
    const newHeight = Math.min(textareaRef.value.scrollHeight, maxHeight);
    textareaRef.value.style.height = newHeight + 'px';

    // If we've reached the max height, stop the watcher
    if (newHeight >= maxHeight && watchStop) {
      watchStop();
      watchStop = null; // Clear the reference
    }
  }
};

const checkContentLength = (event: Event) => {
  const target = event.target as HTMLTextAreaElement;
  if (target.value.length <= localMaxLength.value) {
    content.value = target.value;
    charCount.value = target.value.length;
  } else {
    // Truncate the input if it exceeds the max length
    content.value = target.value.slice(0, props.maxLength);
    charCount.value = localMaxLength.value;
    target.value = content.value; // Update the textarea value
  }
  adjustTextareaHeight();
  emit('update:content', content.value);
};

// 6. Watchers
watchStop = watch(content, (newContent) => {
  emit('update:content', newContent);
  adjustTextareaHeight();
});

// 7. Lifecycle Hooks
onMounted(() => {
  document.addEventListener('click', handleClickOutside);
  document.addEventListener('keydown', handleEscapeKey);
  adjustTextareaHeight();
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
  document.removeEventListener('keydown', handleEscapeKey);
});
</script>

<template>
  <div
    class="relative"
    @mouseenter="handleMouseEnter"
    @mouseleave="handleMouseLeave">
    <textarea
      ref="textareaRef"
      v-model="content"
      @input="checkContentLength"
      :maxlength="maxLength"
      class="max-h-[400px] min-h-24 w-full resize-none overflow-y-auto rounded-md border-gray-300 bg-white
            p-4 font-mono text-base
            leading-[1.2] tracking-wide
            shadow-sm transition-colors duration-200 placeholder:text-gray-400
            focus:border-brandcomp-500 focus:ring-brandcomp-500
            dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:placeholder:text-gray-500"
      name="secret"
      autofocus
      autocomplete="off"
      :placeholder="$t('web.COMMON.secret_placeholder')"
      :aria-label="$t('enter-the-secret-content-to-share-here')">
    </textarea>

    <!--
      Generally speaking, v-if has higher toggle costs while v-show has higher
      initial render costs. So prefer v-show if you need to toggle something
      very often, and prefer v-if if the condition is unlikely to change at
      runtime. -- https://vuejs.org/guide/essentials/conditional.html#v-if-vs-v-show
    -->
    <div
      v-if="showCounter"
      class="pointer-events-none select-none hidden
            rounded-full bg-white px-3 py-1
            text-sm text-gray-400
            shadow-sm
            transition-colors duration-200
            dark:bg-gray-800 dark:text-gray-500">
      {{ $t('formattedcharcount-formattedmaxlength-chars', [formattedCharCount, formattedMaxLength]) }}
    </div>

    <div
      v-if="withDomainDropdown"
      class="absolute bottom-4 right-4">
      <div
        class="relative inline-block text-left"
        ref="dropdownRef">
        <button
          type="button"
          @click="toggleDropdown"
          class="inline-flex w-full items-center justify-between rounded-md border border-gray-300
              bg-white px-4 py-2 text-sm font-medium
              text-gray-700 transition-colors duration-200 hover:bg-gray-50
              focus:outline-none focus:ring-2
              focus:ring-brandcomp-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300
              dark:hover:bg-gray-700 dark:focus:ring-offset-gray-800">
          <span class="max-w-[150px] truncate">
            {{ selectedDomain || 'Select Domain' }}
          </span>
          <OIcon
            collection="heroicons"
            name="chevron-down-16-solid"
            class="ml-2 size-5 shrink-0 text-gray-400 dark:text-gray-500"
            aria-hidden="true"
          />
        </button>

        <div
          v-if="isOpen"
          class="absolute right-0 z-50 mt-2 max-h-60 w-56 origin-top-right
              overflow-y-auto rounded-md
              bg-white shadow-lg ring-1 ring-black
              ring-opacity-5 focus:outline-none
              dark:bg-gray-800 dark:ring-gray-700">
          <div
            class="py-1"
            role="menu"
            aria-orientation="vertical"
            aria-labelledby="options-menu">
            <a
              v-for="domain in availableDomains"
              :key="domain"
              href="#"
              @click.prevent="selectDomain(domain)"
              class="block px-4 py-2 text-sm text-gray-700 transition-colors
                  duration-200 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300
                  dark:hover:bg-gray-700 dark:hover:text-white"
              role="menuitem">
              {{ domain }}
            </a>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Ensure the dropdown container has a higher z-index than the input field */
.absolute {
  z-index: 40;
}
</style>
