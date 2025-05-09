// src/components/SplitButton.vue

<script setup lang="ts">
  import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  // Action types for the button
  type ActionType = 'create-link' | 'generate-password';

  const props = defineProps({
    content: { type: String, default: '' },
    withGenerate: { type: Boolean, default: false },
    disabled: { type: Boolean, default: false },
    disableGenerate: { type: Boolean, default: false },
    cornerClass: { type: String, default: '' },
    primaryColor: { type: String, default: '' },
    buttonTextLight: { type: Boolean, default: undefined },
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

  const processCornerClass = (cornerClass: string | undefined): { leftCorner: string, rightCorner: string } => {
    if (!cornerClass) {
      return { leftCorner: 'rounded-l-xl', rightCorner: 'rounded-r-xl' };
    }

    // Extract radius size from cornerClass (e.g., 'lg', 'md', 'sm', etc.)
    const match = cornerClass.match(/rounded-(\w+)/);
    const size = match ? match[1] : 'xl';

    return {
      leftCorner: `rounded-l-${size}`,
      rightCorner: `rounded-r-${size}`,
    };
  }

  // Get the correct equivalent left and right corner classes
  const corners = computed(() => processCornerClass(props.cornerClass));
  const textColorClass = computed(() => props.buttonTextLight ? 'text-white' : 'text-gray-800');
  // Left button focus ring (respects left corner rounding)
  const leftButtonFocusClass = computed(() => `${corners.value.leftCorner}`);

  // Right button focus ring (respects right corner rounding)
  const rightButtonFocusClass = computed(() => `${corners.value.rightCorner}`);

  // Compute the ring color based on primaryColor availability
  const ringColorStyle = computed(() => {
    return props.primaryColor ? props.primaryColor : 'var(--color-brand-600)';
  });

  // Button labels and icons based on selected action
  const buttonConfig = computed(() => {
    const configs = {
      'create-link': {
        label: t('web.LABELS.create-link-short'),
        icon: '<rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />',
        emit: () => emit('create-link'),
      },
      'generate-password': {
        label: t('web.COMMON.button_generate_secret_short'),
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
      aria-live="assertive">
      {{ buttonConfig.label }} mode activated
    </div>
    <button
      type="submit"
      :class="[
        corners.leftCorner,
        textColorClass,
        leftButtonFocusClass,
        'flex items-center justify-center gap-2 px-4 py-3 text-lg font-semibold transition-colors',
        'focus:z-10 focus:outline-none focus:ring-2 focus:ring-offset-2 dark:focus:ring-offset-slate-900',
        {
          'cursor-not-allowed opacity-60 disabled:hover:opacity-70 dark:opacity-60': isMainButtonDisabled,
        },
      ]"
      :style="{
        backgroundColor: `${primaryColor}`,
        borderColor: `${primaryColor}`,
        '--tw-ring-color': ringColorStyle,
      }"
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
          v-html="buttonConfig.icon"
        />
      </span>
      <span>{{ buttonConfig.label }}</span>
    </button>

    <!-- prettier-ignore-attribute class -->
    <button
      type="button"
      :class="[
        corners.rightCorner,
        textColorClass,
        rightButtonFocusClass,
        'flex items-center justify-center',
        'focus:z-10 focus:outline-none focus:ring-2 focus:ring-offset-2 dark:focus:ring-offset-slate-900',
        'border-l p-3 transition-colors',
        'hover:opacity-100',
      ]"
      :style="{
        backgroundColor: `${primaryColor}`,
        borderColor: `${primaryColor}`,
        '--tw-ring-color': ringColorStyle,
      }"
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
      :class="cornerClass"
      class="absolute right-0 top-full z-10 mt-1 w-52
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
              ry="2"
            />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </span>
        <span>{{ $t('web.LABELS.create-link-short') }}</span>
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
        <span>{{ $t('web.COMMON.button_generate_secret_short') }}</span>
      </button>
    </div>
  </div>
</template>
