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
  import OIcon from '@/components/icons/OIcon.vue';
  import FancyIcon from '@/components/ctas/FancyIcon.vue';
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

  // Keyboard navigation
  onKeyStroke('Space', (e) => {
    if (document.activeElement === buttonRef.value) {
      e.preventDefault();
      isOpen.value = !isOpen.value;
    }
  });

  // Arrow key navigation
  onKeyStroke(['ArrowDown', 'ArrowUp'], (e) => {
    if (!props.availableDomains?.length) return;

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
    if (isOpen.value && activeIndex.value >= 0) {
      e.preventDefault();
      const domain = props.availableDomains?.[activeIndex.value];
      if (domain) selectDomain(domain);
    }
  });

  onKeyStroke('Escape', () => {
    if (isOpen.value) {
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
  <div
    v-if="withDomainDropdown"
    :title="$t('link-preview')"
    class="mb-2 p-3 rounded-lg bg-gray-50 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 border-dashed shadow-sm transition-all duration-200 hover:shadow-md hover:border-gray-400 dark:hover:border-gray-500">
    <div class="flex items-center font-mono text-gray-600 dark:text-gray-400">
      <OIcon
        collection="heroicons"
        name="globe-alt-solid"
        class="size-5 shrink-0 text-gray-400 dark:text-gray-500 mr-2" />

      <div
        ref="dropdownRef"
        class="relative flex-1 min-w-0">
        <button
          ref="buttonRef"
          type="button"
          @click="isOpen = !isOpen"
          class="w-full text-left appearance-none bg-transparent group cursor-pointer px-0 flex items-center font-brand focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 focus:ring-offset-gray-50 dark:focus:ring-offset-gray-800 rounded-sm transition-shadow"
          aria-haspopup="listbox"
          :aria-expanded="isOpen"
          :aria-label="`Select domain. Currently selected: ${selectedDomain}. Press Space or Enter to open dropdown`">
          <div class="flex items-center min-w-0 w-full">
            <!-- Prefix stays the same -->
            <span class="text-gray-500 shrink-0 text-sm">https://</span>

            <!-- Domain and suffix container -->
            <div class="flex min-w-0 flex-grow overflow-hidden">
              <!-- Domain part -->
              <span
                class="border-b-2 border-transparent group-hover:border-brandcomp-500 text-slate-900 dark:text-gray-100 dark:group-hover:border-brandcomp-400 truncate max-w-[92%]">
                {{ selectedDomain }}
              </span>

              <!-- Suffix moves next to domain -->
              <span class="flex min-w-0 flex-1 items-center overflow-hidden">
                <span
                  class="truncate text-sm text-gray-600 dark:text-gray-400">
                  /secret/abc23456
                </span>
              </span>
            </div>

            <!-- Dropdown icon -->
            <span class="shrink-0 ml-1">
              <OIcon
                collection="heroicons"
                name="chevron-down"
                class="h-4 w-4 text-gray-950 group-hover:text-brandcomp-500 dark:group-hover:text-brandcomp-400" />
            </span>
          </div>
        </button>

        <div
          v-if="isOpen"
          class="absolute z-10 w-full mt-1 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md shadow-lg max-w-full overflow-hidden"
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
            class="p-2 cursor-pointer flex items-center w-full"
            role="option"
            :aria-selected="domain === selectedDomain"
            :class="[
              'p-2 flex items-center gap-2 transition-colors',
              'cursor-pointer select-none',
              {
                'bg-brandcomp-100 dark:bg-brandcomp-800 text-brandcomp-800 dark:text-brandcomp-200 font-medium':
                  domain === selectedDomain || index === activeIndex,
                'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-brandcomp-700 dark:hover:text-brandcomp-300':
                  domain !== selectedDomain && index !== activeIndex,
              },
            ]">
            <OIcon
              v-if="domain === selectedDomain"
              collection="heroicons"
              name="check"
              class="h-4 w-4 shrink-0" />
            <span :class="{ 'pl-6': !(domain === selectedDomain) }" class="truncate min-w-0 flex-1">{{ domain }}</span>
          </div>
          <div
            v-if="!authenticated"
            class="p-2 cursor-pointer flex items-center border-t border-gray-200 dark:border-gray-700"
            role="option"
            :class="[
              'p-2 flex items-center gap-2 transition-colors',
              'cursor-pointer select-none',
              'text-brandcomp-600 dark:text-brandcomp-400 hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-brandcomp-700 dark:hover:text-brandcomp-300',
            ]">
              <FancyIcon />
            <router-link to="/pricing" class="w-full block py-1 font-medium hover:underline">{{ $t('upgrade-for-yourdomain') }}</router-link>
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
