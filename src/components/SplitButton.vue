// src/components/SplitButton.vue

<script setup lang="ts">
  import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

  // Action types for the button
  type ActionType = 'create-link' | 'generate-password';

  const props = defineProps({
    content: { type: String, default: '' },
    withGenerate: { type: Boolean, default: false },
    disabled: { type: Boolean, default: false },
    disableGenerate: { type: Boolean, default: false },
  });

  const emit = defineEmits(['generate-password', 'create-link', 'update:action']);

  const isDropdownOpen = ref(false);
  const buttonRef = ref<HTMLElement | null>(null);
  const selectedAction = ref<ActionType>('create-link');
  const isContentEmpty = computed(() => !props.content.trim());
  const isMainButtonDisabled = computed(() => {
    // Disable the Create Link action when no content
    if (selectedAction.value === 'create-link') {
      return props.disabled || (!isContentEmpty.value && !props.content);
    }
    // Disable Generate Password action when there IS content
    if (selectedAction.value === 'generate-password') {
      return props.disableGenerate;
    }
    return false;
  });

  // Button labels and icons based on selected action
  const buttonConfig = computed(() => {
    const configs = {
      'create-link': {
        label: 'Create Link',
        icon: '<rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />',
        emit: () => emit('create-link'),
      },
      'generate-password': {
        label: 'Generate Password',
        icon: '<path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />',
        emit: () => emit('generate-password'),
      },
    };
    return configs[selectedAction.value];
  });

  function handleMainClick() {
    if (isMainButtonDisabled.value) return;
    buttonConfig.value.emit();
  }

  function handleDropdownToggle() {
    isDropdownOpen.value = !isDropdownOpen.value;
  }

  function setAction(action: ActionType) {
    selectedAction.value = action;
    isDropdownOpen.value = false;
    emit('update:action', action);
  }

  function handleClickOutside(event: MouseEvent) {
    if (buttonRef.value && !buttonRef.value.contains(event.target as Node)) {
      isDropdownOpen.value = false;
    }
  }

  onMounted(() => {
    document.addEventListener('click', handleClickOutside);
    // Emit initial action
    emit('update:action', selectedAction.value);
  });

  onBeforeUnmount(() => {
    document.removeEventListener('click', handleClickOutside);
  });
</script>

<template>
  <div
    class="relative inline-flex w-full sm:w-auto"
    ref="buttonRef">
    <!-- Visually hidden announcement for screen readers when action changes -->
    <div
      v-if="selectedAction"
      class="sr-only"
      aria-live="assertive">{{ buttonConfig.label }} mode activated</div>
    <button
      type="submit"
      :class="[
        'flex items-center justify-center gap-2 rounded-l-lg px-4 py-3 text-lg font-semibold text-white transition-colors',
        'bg-brand-500 hover:bg-brand-600 dark:bg-brand-600 dark:hover:bg-brand-700',
        'focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-slate-900',
        {
          'cursor-not-allowed bg-brand-500/60 disabled:hover:bg-brand-500/70 dark:bg-brand-600/60 dark:text-white/50': isMainButtonDisabled,
        },
      ]"
      @click="handleMainClick"
      :disabled="isMainButtonDisabled"
      :aria-label="buttonConfig.label">
      <span class="flex items-center text-current">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          class="size-5"
          v-html="buttonConfig.icon" />
      </span>
      <span>{{ buttonConfig.label }}</span>
    </button>

    <!-- prettier-ignore-attribute class -->
    <button
      type="button"
      class="flex items-center justify-center rounded-r-lg
        border-l border-white/30 bg-brand-500
        p-3 text-white transition-colors hover:bg-brand-700
        focus:outline-none focus:ring-2
        focus:ring-brand-500 focus:ring-offset-2 dark:bg-brand-600 dark:hover:bg-brand-700
        dark:focus:ring-offset-slate-900"
      @click="handleDropdownToggle"
      aria-label="Show more actions"
      :aria-expanded="isDropdownOpen"
      aria-haspopup="true"
      aria-controls="split-button-dropdown">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        class="size-5">
        <polyline points="6 9 12 15 18 9" />
      </svg>
    </button>

    <!-- prettier-ignore-attribute class -->
    <div
      v-if="isDropdownOpen"
      id="split-button-dropdown"
      class="absolute right-0 top-full z-10 mt-1 w-52 rounded-md
        bg-white shadow-lg dark:bg-gray-800">
      <!-- prettier-ignore-attribute class -->
      <button
        type="button"
        class="flex w-full items-center gap-2 border-0 bg-transparent px-4
          py-2.5 text-left text-gray-800 transition-colors hover:bg-gray-100
          dark:text-gray-200 dark:hover:bg-gray-700"
        @click="setAction('create-link')">
        <span class="flex items-center text-current">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-5">
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

      <!-- prettier-ignore-attribute class -->
      <button
        type="button"
        v-if="props.withGenerate"
        class="flex w-full items-center gap-2 border-0 bg-transparent px-4 py-2.5
          text-left text-gray-800 transition-colors hover:bg-gray-100
          dark:text-gray-200 dark:hover:bg-gray-700"
        @click="setAction('generate-password')">
        <span class="flex items-center text-brand-500 dark:text-brand-400">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-5">
            <path
              d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
          </svg>
        </span>
        <span>Generate Password</span>
      </button>
    </div>
  </div>
</template>
