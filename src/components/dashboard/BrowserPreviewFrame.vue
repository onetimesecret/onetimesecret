<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';

interface Props {
  domain: string;
  browserType?: 'safari' | 'edge';
}

withDefaults(defineProps<Props>(), {
  browserType: 'safari'
});

defineEmits<{
  (e: 'toggle-browser'): void;
}>();
</script>


<template>
  <div
    class="relative mx-auto max-w-full overflow-hidden rounded-xl border border-gray-200 shadow-2xl dark:border-gray-700">
    <!-- Browser Top Bar -->
    <div
      v-if="browserType === 'safari'"
      class="flex items-center space-x-2 border-b border-gray-200 bg-gray-100 p-3 dark:border-gray-700 dark:bg-gray-800">
      <!-- Safari Controls -->
      <div class="group/controls flex space-x-2">
        <!-- Close button -->
        <button
          @click="$emit('toggle-browser')"
          class="size-3 rounded-full bg-[#FF5F57] transition-colors hover:bg-[#E04940]"
          aria-label="$t('switch-to-edge-browser-view')">
          <svg
            class="m-auto size-2 opacity-0 transition-opacity group-hover/controls:opacity-100"
            viewBox="0 0 8 8"
            fill="none"
            stroke="rgba(0, 0, 0, 0.4)"
            stroke-width="1.5">
            <path d="M1.5 1.5l5 5m0-5l-5 5" />
          </svg>
        </button>

        <!-- Minimize button -->
        <button
          class="size-3 rounded-full bg-[#FFBD2E] transition-colors hover:bg-[#E0A323]"
          aria-label="$t('minimize-window')">
          <svg
            class="m-auto size-2 opacity-0 transition-opacity group-hover/controls:opacity-100"
            viewBox="0 0 8 8"
            fill="none"
            stroke="rgba(0, 0, 0, 0.4)"
            stroke-width="1.5">
            <path d="M2 4h4" />
          </svg>
        </button>

        <!-- Maximize button -->
        <button
          class="size-3 rounded-full bg-[#28C840] transition-colors hover:bg-[#1FA833]"
          aria-label="$t('maximize-window')">
          <svg
            class="m-auto size-2 opacity-0 transition-opacity group-hover/controls:opacity-100"
            viewBox="0 0 8 8"
            fill="none"
            stroke="rgba(0, 0, 0, 0.4)"
            stroke-width="1.5">
            <path d="M1.5 1.5h5v5h-5z" />
          </svg>
        </button>
      </div>
      <!-- Safari/Edge Address Bar -->
      <div class="mx-2 flex-1 sm:mx-4">
        <div
          class="flex items-center justify-between rounded-md bg-white px-2 py-1.5 text-sm text-gray-600 dark:bg-gray-700 dark:text-gray-300 sm:px-3">
          <!-- Make URL text responsive -->
          <div class="flex items-center overflow-hidden">
            <svg
              class="mr-2 size-4 text-gray-400"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
            <span class="shrink-0 text-green-400">https://</span>
            <span class="truncate font-bold">{{ domain }}</span>
            <span class="hidden opacity-50 sm:inline">/secret/abcd1234</span>
          </div>
          <!-- Preview Badge - Safari -->
          <span
            class="ml-3 inline-flex items-center rounded bg-brandcomp-100 px-2 py-0.5 text-xs font-medium text-brand-800 dark:bg-brandcomp-900 dark:text-brandcomp-200">
            <svg
              class="mr-1 size-3"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
              />
            </svg>
            {{ $t('preview') }}
          </span>
        </div>
      </div>
    </div>

    <div
      v-else
      class="flex flex-col border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <!-- Edge Window Controls -->
      <div class="flex items-center justify-between bg-gray-100 px-4 py-2 dark:bg-gray-900">
        <div class="flex items-center space-x-2">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4"
            viewBox="0 0 16 16">
            <g
              fill="currentColor"
              class="text-gray-600 dark:text-gray-300">
              <path
                d="M9.482 9.341c-.069.062-.17.153-.17.309c0 .162.107.325.3.456c.877.613 2.521.54 2.592.538h.002c.667 0 1.32-.18 1.894-.519A3.84 3.84 0 0 0 16 6.819c.018-1.316-.44-2.218-.666-2.664l-.04-.08C13.963 1.487 11.106 0 8 0A8 8 0 0 0 .473 5.29C1.488 4.048 3.183 3.262 5 3.262c2.83 0 5.01 1.885 5.01 4.797h-.004v.002c0 .338-.168.832-.487 1.244l.006-.006z"
              />
              <path
                d="M.01 7.753a8.14 8.14 0 0 0 .753 3.641a8 8 0 0 0 6.495 4.564a5 5 0 0 1-.785-.377h-.01l-.12-.075a5.5 5.5 0 0 1-1.56-1.463A5.543 5.543 0 0 1 6.81 5.8l.01-.004l.025-.012c.208-.098.62-.292 1.167-.285q.194.001.384.033a4 4 0 0 0-.993-.698l-.01-.005C6.348 4.282 5.199 4.263 5 4.263c-2.44 0-4.824 1.634-4.99 3.49m10.263 7.912q.133-.04.265-.084q-.153.047-.307.086z"
              />
              <path
                d="M10.228 15.667a5 5 0 0 0 .303-.086l.082-.025a8.02 8.02 0 0 0 4.162-3.3a.25.25 0 0 0-.331-.35q-.322.168-.663.294a6.4 6.4 0 0 1-2.243.4c-2.957 0-5.532-2.031-5.532-4.644q.003-.203.046-.399a4.54 4.54 0 0 0-.46 5.898l.003.005c.315.441.707.821 1.158 1.121h.003l.144.09c.877.55 1.721 1.078 3.328.996"
              />
            </g>
          </svg>
          <span class="text-xs text-gray-600 dark:text-gray-300">{{ $t('microsoft-edge') }}</span>
        </div>

        <div class="flex space-x-4">
          <button class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
            <svg
              class="size-4"
              fill="currentColor"
              viewBox="0 0 16 16">
              <path d="M14 8v1H3V8h11z" />
            </svg>
          </button>
          <button class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
            <svg
              class="size-4"
              fill="currentColor"
              viewBox="0 0 16 16">
              <path d="M3 3v10h10V3H3zm9 9H4V4h8v8z" />
            </svg>
          </button>
          <button
            @click="$emit('toggle-browser')"
            class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            aria-label="$t('switch-to-safari-browser-view')">
            <svg
              class="size-4"
              fill="currentColor"
              viewBox="0 0 16 16">
              <path
                d="M4.646 4.646a.5.5 0 0 1 .708 0L8 7.293l2.646-2.647a.5.5 0 0 1 .708.708L8.707 8l2.647 2.646a.5.5 0 0 1-.708.708L8 8.707l-2.646 2.647a.5.5 0 0 1-.708-.708L7.293 8 4.646 5.354a.5.5 0 0 1 0-.708z"
              />
            </svg>
          </button>
        </div>
      </div>
      <!-- Edge Address Bar -->
      <div class="flex items-center px-4 py-2">
        <div
          class="flex flex-1 items-center justify-between rounded-lg bg-gray-100 px-2 py-1.5 text-sm text-gray-600 dark:bg-gray-700 dark:text-gray-300 sm:px-3">
          <!-- Make URL text responsive -->
          <div class="flex items-center overflow-hidden">
            <svg
              class="mr-2 size-4 text-blue-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
            <span class="shrink-0 text-green-400">https://</span>
            <span class="truncate font-bold">{{ domain }}</span>
            <span class="hidden opacity-50 sm:inline">/secret/abcd1234</span>
          </div>
          <!-- Preview Badge - Edge -->
          <span
            class="ml-3 inline-flex items-center rounded bg-brandcomp-100 px-2 py-0.5 text-xs font-medium text-brand-800 dark:bg-brandcomp-900 dark:text-brandcomp-200">
            <svg
              class="mr-1 size-3"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
              />
            </svg>
            {{ $t('preview-0') }}
          </span>
        </div>
      </div>
    </div>

    <!-- Content Area -->
    <div class="relative bg-white dark:bg-gray-800">
      <slot></slot>
    </div>

    <!-- Info text - Responsive padding -->
    <div class="px-3 pb-2 pt-3 sm:px-6 sm:pt-6">
      <div
        class="flex items-center gap-2 rounded-lg bg-gray-50 p-2 text-xs italic dark:bg-gray-900 sm:gap-3 sm:p-3 sm:text-sm">
        <OIcon
          collection="mdi"
          name="forum"
          class="size-5 shrink-0"
        />
        <p>{{ $t('preview-of-the-secret-link-page-for-recipients') }}</p>
      </div>
    </div>
  </div>
</template>
