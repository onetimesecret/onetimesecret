<!-- src/shared/components/navigation/DomainScopeSwitcher.vue -->

<!--
  Domain Scope Switcher Component

  Allows consultants to switch between their custom domains in the workspace header.
  Only visible when user has multiple domains configured.

  Key behaviors:
  - Shows current domain scope with visual indicator
  - Dropdown menu with all available domains
  - Persists selection via useDomainScope composable
  - Compact header-friendly design
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useClickOutside } from '@/shared/composables/useClickOutside';
import { useDomainScope } from '@/shared/composables/useDomainScope';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const {
  currentScope,
  availableDomains,
  hasMultipleScopes,
  isScopeActive,
  setScope,
} = useDomainScope();

const isOpen = ref(false);
const dropdownRef = ref<HTMLElement | null>(null);
const listboxRef = ref<HTMLElement | null>(null);
const activeIndex = ref(0);

/**
 * Get display name for a domain
 */
const getDisplayName = (domain: string): string => {
  if (domain === currentScope.value.domain && currentScope.value.isCanonical) {
    return t('web.domains.scope_personal');
  }
  return domain;
};

/**
 * Check if a domain is the currently selected scope
 */
const isCurrentScope = (domain: string): boolean => domain === currentScope.value.domain;

/**
 * Toggle the dropdown menu
 */
const toggleDropdown = (): void => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    setActiveIndexFromCurrent();
    setTimeout(() => {
      focusActiveItem();
    }, 0);
  }
};

/**
 * Close the dropdown menu
 */
const closeDropdown = (): void => {
  isOpen.value = false;
};

/**
 * Set active index based on current selection
 */
const setActiveIndexFromCurrent = (): void => {
  const currentDomain = currentScope.value.domain;
  const index = availableDomains.value.findIndex(d => d === currentDomain);
  activeIndex.value = index >= 0 ? index : 0;
};

/**
 * Focus the active item in the listbox
 */
const focusActiveItem = (): void => {
  if (!listboxRef.value) return;

  const items = listboxRef.value.querySelectorAll('[role="option"]');
  if (items[activeIndex.value]) {
    (items[activeIndex.value] as HTMLElement).focus();
  }
};

/**
 * Handle domain selection
 */
const selectDomain = (domain: string): void => {
  setScope(domain);
  closeDropdown();
};

/**
 * Handle keyboard navigation
 */
const handleKeyDown = (event: KeyboardEvent): void => {
  if (!isOpen.value) {
    if (event.key === 'Enter' || event.key === ' ' || event.key === 'ArrowDown') {
      event.preventDefault();
      toggleDropdown();
    }
    return;
  }

  switch (event.key) {
    case 'Escape':
      event.preventDefault();
      closeDropdown();
      break;
    case 'ArrowDown':
      event.preventDefault();
      activeIndex.value = (activeIndex.value + 1) % availableDomains.value.length;
      focusActiveItem();
      break;
    case 'ArrowUp':
      event.preventDefault();
      activeIndex.value = (activeIndex.value - 1 + availableDomains.value.length) % availableDomains.value.length;
      focusActiveItem();
      break;
    case 'Home':
      event.preventDefault();
      activeIndex.value = 0;
      focusActiveItem();
      break;
    case 'End':
      event.preventDefault();
      activeIndex.value = availableDomains.value.length - 1;
      focusActiveItem();
      break;
    case 'Enter':
    case ' ':
      event.preventDefault();
      selectDomain(availableDomains.value[activeIndex.value]);
      break;
  }
};

/**
 * Handle option activation via click or keyboard
 */
const handleOptionActivation = (domain: string, index: number): void => {
  activeIndex.value = index;
  selectDomain(domain);
};

// Close dropdown when clicking outside
useClickOutside(dropdownRef, closeDropdown);

// Computed: should component be visible
const shouldShow = computed(() => isScopeActive.value && hasMultipleScopes.value);
</script>

<template>
  <div
    v-if="shouldShow"
    ref="dropdownRef"
    class="relative inline-flex">
    <!-- Trigger Button -->
    <button
      @click="toggleDropdown"
      @keydown="handleKeyDown"
      class="group inline-flex items-center gap-2 rounded-lg
             bg-gray-100 px-3 py-1.5 text-sm font-medium
             text-gray-700 transition-colors duration-150
             hover:bg-gray-200 hover:text-gray-900
             focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
             dark:bg-gray-800 dark:text-gray-300
             dark:hover:bg-gray-700 dark:hover:text-white
             dark:focus:ring-offset-gray-900"
      :aria-expanded="isOpen"
      aria-haspopup="listbox"
      :aria-label="t('web.domains.scope_switch_label')">
      <!-- Domain Icon -->
      <OIcon
        collection="heroicons"
        name="globe-alt"
        class="size-4 text-gray-500 group-hover:text-brand-500
               dark:text-gray-400 dark:group-hover:text-brand-400"
        aria-hidden="true" />

      <!-- Current Domain Display -->
      <span class="max-w-[150px] truncate">
        {{ currentScope.displayName }}
      </span>

      <!-- Chevron -->
      <OIcon
        collection="heroicons"
        :name="isOpen ? 'chevron-up-solid' : 'chevron-down-solid'"
        class="size-4 text-gray-400 transition-transform"
        aria-hidden="true" />
    </button>

    <!-- Dropdown Menu -->
    <Transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95">
      <ul
        v-if="isOpen"
        ref="listboxRef"
        class="absolute left-0 top-full z-50 mt-1 max-h-60 w-max min-w-[220px] max-w-xs
               overflow-auto rounded-lg bg-white py-1 text-sm shadow-lg
               ring-1 ring-black/5 focus:outline-none
               dark:bg-gray-800 dark:ring-gray-700"
        role="listbox"
        :aria-label="t('web.domains.scope_list_label')"
        @keydown="handleKeyDown">
        <!-- Header -->
        <li
          class="px-3 py-2 font-brand text-xs font-semibold uppercase tracking-wider
                 text-gray-500 dark:text-gray-400">
          {{ t('web.domains.scope_header') }}
        </li>

        <!-- Domain Options -->
        <li
          v-for="(domain, index) in availableDomains"
          :key="domain"
          class="relative cursor-pointer select-none py-2 pl-3 pr-9
                 text-gray-700 transition-colors duration-150
                 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-700"
          :class="{ 'bg-brand-50 dark:bg-brand-900/20': isCurrentScope(domain) }"
          role="option"
          tabindex="0"
          :aria-selected="isCurrentScope(domain)"
          :id="`domain-scope-option-${index}`"
          @click="handleOptionActivation(domain, index)"
          @keydown.enter.prevent="handleOptionActivation(domain, index)"
          @keydown.space.prevent="handleOptionActivation(domain, index)">
          <span class="flex items-center gap-2">
            <!-- Domain-specific icon -->
            <OIcon
              collection="heroicons"
              :name="isCurrentScope(domain) && currentScope.isCanonical ? 'home' : 'globe-alt'"
              class="size-4 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />

            <!-- Domain Name -->
            <span
              class="block truncate"
              :class="{ 'font-semibold': isCurrentScope(domain) }">
              {{ getDisplayName(domain) }}
            </span>
          </span>

          <!-- Selected Checkmark -->
          <span
            v-if="isCurrentScope(domain)"
            class="absolute inset-y-0 right-0 flex items-center pr-3">
            <OIcon
              collection="heroicons"
              name="check-20-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </span>
        </li>
      </ul>
    </Transition>
  </div>
</template>
