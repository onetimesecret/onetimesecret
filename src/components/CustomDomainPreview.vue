/** eslint-disable tailwindcss/migration-from-tailwind-2 */
<!-- src/components/CustomDomainPreview.vue -->

<script setup lang="ts">
  /**
   * CustomDomainPreview Component
   *
   * Technical Implementation:
   * - Uses composition API with dedicated composables:
   *   - useDropdown: Manages dropdown state and interactions
   *   - useDomainDropdown: Handles domain selection state
   *
   * Props:
   * @prop {string[]} [availableDomains] - List of available domains for selection
   * @prop {boolean} [withDomainDropdown=false] - Enable/disable domain selection
   *
   * Events:
   * @emits {string} update:selected-domain - Emitted when domain selection changes
   * @see {@link useDropdown} For dropdown behavior implementation
   * @see {@link useDomainDropdown} For domain selection implementation
   */
  import FancyIcon from '@/components/ctas/FancyIcon.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useDomainDropdown } from '@/composables/useDomainDropdown';
  import { useDropdown } from '@/composables/useDropdown';
  import { WindowService } from '@/services/window.service';
  import { onClickOutside, onKeyStroke } from '@vueuse/core';
  import { ref, watch } from 'vue';

  const props = withDefaults(
    defineProps<{
      availableDomains?: string[];
      initialDomain?: string;
      withDomainDropdown?: boolean;
    }>(),
    {
      availableDomains: undefined,
      initialDomain: '',
      withDomainDropdown: false,
    }
  );

  const emit = defineEmits<{
    'update:selected-domain': [domain: string];
  }>();

  const { isOpen, dropdownRef, close } = useDropdown();
  const { selectedDomain, updateSelectedDomain, isLoading } = useDomainDropdown();

  const activeIndex = ref(-1);
  const buttonRef = ref<HTMLButtonElement | null>(null);
  const authenticated = WindowService.get('authenticated') ?? false;

  const selectDomain = (domain: string) => {
    updateSelectedDomain(domain);
    emit('update:selected-domain', domain);
    close();
  };

  onClickOutside(dropdownRef, () => {
    close();
  });

  // Keyboard navigation for Space key
  onKeyStroke('Space', (e) => {
    // This is already checking for button focus, which is correct
    if (document.activeElement === buttonRef.value) {
      e.preventDefault();
      isOpen.value = !isOpen.value;
    }
  });

  // Arrow key navigation
  onKeyStroke(['ArrowDown', 'ArrowUp'], (e) => {
    // Only handle arrow keys when the component is focused or dropdown is open
    if (!props.availableDomains?.length) return;

    // Check if either the button is focused or the dropdown is open
    const isComponentFocused = document.activeElement === buttonRef.value || isOpen.value;
    if (!isComponentFocused) return;

    e.preventDefault();
    if (!isOpen.value) {
      isOpen.value = true;
      activeIndex.value = 0;
      return;
    }

    if (e.key === 'ArrowDown') {
      activeIndex.value = (activeIndex.value + 1) % props.availableDomains?.length;
    } else {
      activeIndex.value =
        activeIndex.value <= 0 ? props.availableDomains.length - 1 : activeIndex.value - 1;
    }
  });

  // Enter to select highlighted item
  onKeyStroke('Enter', (e) => {
    // Only handle when dropdown is open and component is focused
    const isComponentFocused = document.activeElement === buttonRef.value || isOpen.value;
    if (isOpen.value && activeIndex.value >= 0 && isComponentFocused) {
      e.preventDefault();
      const domain = props.availableDomains?.[activeIndex.value];
      if (domain) selectDomain(domain);
    }
  });

  onKeyStroke('Escape', () => {
    // Only handle when dropdown is open and component is focused
    const isComponentFocused = document.activeElement === buttonRef.value || isOpen.value;
    if (isOpen.value && isComponentFocused) {
      close();
      buttonRef.value?.focus();
    }
  });

  // Reset active index when dropdown closes
  watch(isOpen, (newValue) => {
    if (!newValue) activeIndex.value = -1;
  });

  // Watch for changes in availableDomains to simulate loading state
  watch(
    () => props.availableDomains,
    (newDomains) => {
      if (!newDomains) {
        isLoading.value = true;
      } else {
        isLoading.value = false;
      }
    },
    { immediate: true }
  );
</script>

<template>
  <!-- prettier-ignore-attribute class -->
  <div
    v-if="withDomainDropdown"
    :title="$t('link-preview')"
    class="mb-0 rounded-lg border border-dashed border-gray-300
      bg-gray-50 p-3 shadow-sm transition-all duration-200
      hover:border-gray-400 hover:shadow-md dark:border-gray-600
      dark:bg-gray-800 dark:hover:border-gray-500">
    <div class="flex items-center font-mono text-gray-600 dark:text-gray-400">
      <OIcon
        collection="heroicons"
        name="globe-alt-solid"
        class="mr-2 size-5 shrink-0 text-gray-400 dark:text-gray-500" />

      <div
        ref="dropdownRef"
        class="relative min-w-0 flex-1">
        <!-- prettier-ignore-attribute class -->
        <button
          ref="buttonRef"
          type="button"
          @click="isOpen = !isOpen"
          class="group flex w-full cursor-pointer appearance-none items-center rounded-sm
            bg-transparent px-0 text-left font-brand transition-shadow
            focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 focus:ring-offset-gray-50
            dark:focus:ring-offset-gray-800"
          aria-haspopup="listbox"
          :aria-expanded="isOpen"
          :aria-label="`Select domain. Currently selected: ${selectedDomain}. Press Space or Enter to open dropdown`">
          <div class="flex w-full min-w-0 items-center">
            <!-- Prefix stays the same -->
            <span class="shrink-0 text-sm text-gray-500">https://</span>

            <!-- Domain and suffix container -->
            <div class="flex min-w-0 grow overflow-hidden">
              <!-- prettier-ignore-attribute class -->
              <span
                class="max-w-[92%] truncate border-b-2 border-transparent text-slate-900
                  group-hover:border-brandcomp-500 dark:text-gray-100 dark:group-hover:border-brandcomp-400">
                {{ selectedDomain }}
              </span>

              <!-- Suffix moves next to domain -->
              <span class="flex min-w-0 flex-1 items-center overflow-hidden">
                <!-- prettier-ignore-attribute class -->
                <span
                  class="truncate bg-gradient-to-r from-gray-600/80 to-transparent bg-clip-text
                  text-sm text-transparent dark:from-gray-400">
                  /secret/abc23456
                </span>
              </span>
            </div>

            <!-- Dropdown icon -->
            <span class="ml-1 shrink-0">
              <!-- prettier-ignore-attribute class -->
              <OIcon
                collection="heroicons"
                name="chevron-down"
                class="size-4 text-gray-950 group-hover:text-brandcomp-500
                  dark:group-hover:text-brandcomp-400" />
            </span>
          </div>
        </button>
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="isOpen"
          class="absolute z-10 mt-1 w-full max-w-full overflow-hidden
            rounded-md border border-gray-300 bg-white shadow-lg
            dark:border-gray-600 dark:bg-gray-800"
          role="listbox">
          <div
            v-if="isLoading"
            class="p-2 text-center text-gray-700 dark:text-gray-300">
            Loading...
          </div>

          <!-- Domains List -->
          <div
            v-else
            v-for="(domain, index) in availableDomains"
            :key="domain"
            @click="selectDomain(domain)"
            class="flex w-full cursor-pointer items-center p-2"
            role="option"
            :aria-selected="domain === selectedDomain"
            :class="[
              'flex items-center gap-2 p-2 transition-colors',
              'cursor-pointer select-none',
              {
                'bg-brandcomp-100 font-medium text-brandcomp-800 dark:bg-brandcomp-800 dark:text-brandcomp-200':
                  domain === selectedDomain || index === activeIndex,
                'text-gray-700 hover:bg-gray-100 hover:text-brandcomp-700 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-brandcomp-300':
                  domain !== selectedDomain && index !== activeIndex,
              },
            ]">
            <OIcon
              v-if="domain === selectedDomain"
              collection="heroicons"
              name="check"
              class="size-4 shrink-0" />
            <!-- prettier-ignore -->
            <span
              :class="{ 'pl-6': !(domain === selectedDomain) }"
              class="min-w-0 flex-1 truncate">{{ domain }}</span>
          </div>
          <!-- prettier-ignore-attribute class -->
          <div
            v-if="!authenticated"
            class="flex cursor-pointer items-center
              border-t border-gray-200 p-2 dark:border-gray-700"
            role="option"
            :class="[
              'flex items-center gap-2 p-2 transition-colors',
              'cursor-pointer select-none',
              'text-brandcomp-600 hover:bg-gray-100 hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:bg-gray-700 dark:hover:text-brandcomp-300',
            ]">
            <FancyIcon />
            <!-- prettier-ignore -->
            <router-link
              to="/pricing"
              class="block w-full py-1
                font-medium hover:underline">{{ $t('upgrade-for-yourdomain') }}</router-link>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
  select {
    -webkit-appearance: none;
    -moz-appearance: none;
    appearance: none;
    border: none;
    text-indent: 0;
    padding-right: 1rem;
  }

  select::-ms-expand {
    display: none;
  }
</style>
