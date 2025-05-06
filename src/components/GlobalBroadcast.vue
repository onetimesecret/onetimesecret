<!-- src/components/GlobalBroadcast.vue -->

<script setup lang="ts">
  import MovingGlobules from '@/components/MovingGlobules.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import DOMPurify from 'dompurify';
  import { computed } from 'vue';
  import { useDismissableBanner } from '@/composables/useDismissableBanner';

  export interface Props {
    content: string | null; // Can contain HTML
    show: boolean;

    expirationDays?: number; // Days until banner reappears after dismissal
  }

  // TypeScript with Composition API
  //
  // Note that default values for mutable reference types (like arrays or
  // objects) should be wrapped in functions to avoid accidental
  // modification and external side effects. This ensures each component
  // instance gets its own copy of the default value.
  //
  // See: https://vuejs.org/guide/typescript/composition-api.html#props-default-values
  const props = withDefaults(defineProps<Props>(), {
    content: 'Welcome to the Global Broadcast!',
    show: false,

    expirationDays: 0, // Default to permanent dismissal
  });

  // Use our composable to handle dismissal state with content-based ID generation
  // The banner ID will be generated asynchronously based on content
  const { isVisible, dismiss } = useDismissableBanner({
    prefix: 'gb', // gb for global-broadcast
    content: props.content
  }, props.expirationDays);

  // Function to decode HTML entities
  function decodeHTMLEntities(html: string) {
    const txt = document.createElement('textarea');
    txt.innerHTML = html;
    return txt.value;
  }

  // Computed property for decoded and sanitized content
  const sanitizedContent = computed(() => {
    const decodedContent = decodeHTMLEntities(props.content ?? '');
    const sanitizeConfig = {
      ALLOWED_TAGS: ['a'],
      ALLOWED_ATTR: ['href', 'target', 'rel', 'class'],
    };
    return DOMPurify.sanitize(decodedContent, sanitizeConfig);
  });

  // Should show banner only if (1) parent says to show it AND (2) user hasn't dismissed it
  const shouldShow = computed(() => props.show && isVisible.value);
</script>

<template>
  <div
    v-if="shouldShow"
    class="relative isolate flex items-center gap-x-6 overflow-hidden bg-gray-50 px-6 py-2.5 dark:bg-gray-900 sm:px-3.5 sm:before:flex-1">
    <div
      class="absolute left-[max(-7rem,calc(50%-52rem))] top-1/2 -z-10 -translate-y-1/2 transform-gpu blur-2xl"
      aria-hidden="true">
      <div
        class="aspect-[577/310] w-[36.0625rem] bg-gradient-to-r from-[#dc4a22] to-[#fcf4e8] opacity-30"
        style="
          clip-path: polygon(
            74.8% 41.9%,
            97.2% 73.2%,
            100% 34.9%,
            92.5% 0.4%,
            87.5% 0%,
            75% 28.6%,
            58.5% 54.6%,
            50.1% 56.8%,
            46.9% 44%,
            48.3% 17.4%,
            24.7% 53.9%,
            0% 27.9%,
            11.9% 74.2%,
            24.9% 54.1%,
            68.6% 100%,
            74.8% 41.9%
          );
        "></div>
    </div>
    <MovingGlobules
      from-colour="#23b5dd"
      to-colour="#dc4a22"
      speed="10s"
      :interval="1000"
      :scale="2" />
    <div
      class="absolute left-[max(45rem,calc(50%+8rem))] top-1/2 -z-10 -translate-y-1/2 transform-gpu blur-2xl"
      aria-hidden="true">
      <div
        class="aspect-[577/310] w-[36.0625rem] bg-gradient-to-r from-[#dc4a22] to-[#fcf4e8] opacity-30"
        style="
          clip-path: polygon(
            74.8% 41.9%,
            97.2% 73.2%,
            100% 34.9%,
            92.5% 0.4%,
            87.5% 0%,
            75% 28.6%,
            58.5% 54.6%,
            50.1% 56.8%,
            46.9% 44%,
            48.3% 17.4%,
            24.7% 53.9%,
            0% 27.9%,
            11.9% 74.2%,
            24.9% 54.1%,
            68.6% 100%,
            74.8% 41.9%
          );
        "></div>
    </div>
    <div class="font-brand text-base leading-6 text-gray-900 dark:text-gray-100">
      <div class="relative flex items-center space-x-3">
        <svg
          class="size-6 opacity-60"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M11 5.882V19.24a1.76 1.76 0 01-3.417.592l-2.147-6.15M18 13a3 3 0 100-6M5.436 13.683A4.001 4.001 0 017 6h1.832c4.1 0 7.625-1.234 9.168-3v14c-1.543-1.766-5.067-3-9.168-3H7a3.988 3.988 0 01-1.564-.317z" />
        </svg>
        <span v-html="sanitizedContent"></span>
      </div>
    </div>
    <div class="flex flex-1 justify-end">
      <button
        type="button"
        @click="dismiss"
        class="-m-3 p-3 focus-visible:outline-offset-[-4px]">
        <span class="sr-only">{{ $t('web.LABELS.dismiss') }}</span>
        <OIcon
          collection="heroicons"
          name="x-mark-16-solid"
          class="size-5 text-gray-900 dark:text-gray-100"
          aria-hidden="true" />
      </button>
    </div>
  </div>
</template>
