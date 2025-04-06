// src/components/SplitButton.vue

<script setup lang="ts">
  import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

  const props = defineProps({
    content: { type: String, default: '' },
    withGenerate: { type: Boolean, default: false },
  });

  const emit = defineEmits(['generate-password', 'create-link']);

  const isDropdownOpen = ref(false);
  const buttonRef = ref(null);
  const isContentEmpty = computed(() => !props.content.trim());
  const isDisabled = computed(() => !isContentEmpty.value && !props.content);

  function handleMainClick() {
    if (isDisabled.value) return;
    emit('create-link');
  }

  function handleDropdownToggle() {
    isDropdownOpen.value = !isDropdownOpen.value;
  }

  function handleGeneratePassword() {
    emit('generate-password');
    isDropdownOpen.value = false;
  }

  function handleClickOutside(event) {
    if (buttonRef.value && !buttonRef.value.contains(event.target)) {
      isDropdownOpen.value = false;
    }
  }

  onMounted(() => {
    document.addEventListener('click', handleClickOutside);
  });

  onBeforeUnmount(() => {
    document.removeEventListener('click', handleClickOutside);
  });
</script>

<template>
  <div
    class="inline-flex relative"
    ref="buttonRef">
    <button
      :class="[
        'flex items-center gap-2 px-4 py-2.5 bg-orange-500 dark:bg-orange-600 text-white font-semibold text-sm rounded-l-md transition-colors',
        'hover:bg-orange-600 dark:hover:bg-orange-700',
        { 'opacity-60 cursor-not-allowed': isDisabled },
      ]"
      @click="handleMainClick"
      :disabled="isDisabled"
      aria-label="Create Link">
      <span class="flex items-center text-current">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2">
          <rect
            x="3"
            y="11"
            width="18"
            height="11"
            rx="2"
            ry="2" />
          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
        </svg>
      </span>
      <span>Create Link</span>
    </button>

    <button
      class="flex items-center justify-center px-3 py-2.5 bg-orange-500 dark:bg-orange-600 text-white rounded-r-md border-l border-white/30 transition-colors hover:bg-orange-600 dark:hover:bg-orange-700"
      @click="handleDropdownToggle"
      aria-label="Show more options"
      :aria-expanded="isDropdownOpen">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2">
        <polyline points="6 9 12 15 18 9" />
      </svg>
    </button>

    <div
      v-if="isDropdownOpen"
      class="absolute top-full right-0 mt-1 bg-white dark:bg-gray-800 rounded-md shadow-lg w-52 z-10">
      <button
        class="flex items-center gap-2 w-full px-4 py-2.5 border-0 bg-transparent text-left text-gray-800 dark:text-gray-200 transition-colors hover:bg-gray-100 dark:hover:bg-gray-700 disabled:opacity-60 disabled:cursor-not-allowed"
        @click="handleMainClick"
        :disabled="isDisabled">
        <span class="flex items-center text-current">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2">
            <rect
              x="3"
              y="11"
              width="18"
              height="11"
              rx="2"
              ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </span>
        <span>Create Link</span>
      </button>

      <button
        v-if="props.withGenerate"
        class="flex items-center gap-2 w-full px-4 py-2.5 border-0 bg-transparent text-left text-gray-800 dark:text-gray-200 transition-colors hover:bg-gray-100 dark:hover:bg-gray-700"
        @click="handleGeneratePassword">
        <span class="flex items-center text-orange-500 dark:text-orange-400">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2">
            <path
              d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
          </svg>
        </span>
        <span>Generate Password</span>
      </button>
    </div>
  </div>
</template>
