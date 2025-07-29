<!-- src/components/JurisdictionToggle.vue -->

<script setup lang="ts">
  import { useClickOutside } from '@/composables/useClickOutside';
  import { useJurisdictionStore } from '@/stores/jurisdictionStore';
  import OIcon from '@/components/icons/OIcon.vue';
  import { computed, ref } from 'vue';
  import type { Jurisdiction } from '@/schemas/models/jurisdiction';

  /* Vue 3 Reactivity Guide: Rules for Store Access
  * ─────────────────────────────────────────
  * ❌ Destructuring breaks reactivity chain:
  *    const { getCurrentJurisdiction } = jurisdictionStore
  *    <template>{{ getCurrentJurisdiction }}</template> => undefined
  *
  * ✓ Computed preserves reactive reference:
  *    const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction)
  *    <template>{{ currentJurisdiction }}</template> => {...}
  *
  * ✓ Direct store access maintains reactivity:
  *    const jurisdictionStore = useJurisdictionStore()
  *    <template>{{ jurisdictionStore.currentJurisdiction }}</template> => {...}
  */
  const jurisdictionStore = useJurisdictionStore();

  // Computed properties with null checks
  const currentJurisdiction = computed<Jurisdiction | null>(
    () => jurisdictionStore.getCurrentJurisdiction
  );
  const jurisdictions = computed<Jurisdiction[]>(
    () => jurisdictionStore.getAllJurisdictions
  );

  const isOpen = ref(false);
  const dropdownRef = ref<HTMLElement | null>(null);
  const listboxRef = ref<HTMLElement | null>(null);
  const activeIndex = ref(0);

  const toggleDropdown = () => {
    isOpen.value = !isOpen.value;
    if (isOpen.value) {
      setActiveIndexFromCurrent();
      setTimeout(() => {
        focusActiveItem();
      }, 0);
    }
  };

  const closeDropdown = () => {
    isOpen.value = false;
  };

  const setActiveIndexFromCurrent = () => {
    const currentId = currentJurisdiction.value?.identifier;
    const index = jurisdictions.value.findIndex(j => j.identifier === currentId);
    activeIndex.value = index >= 0 ? index : 0;
  };

  const focusActiveItem = () => {
    if (!listboxRef.value) return;

    const items = listboxRef.value.querySelectorAll('[role="option"]');
    if (items[activeIndex.value]) {
      (items[activeIndex.value] as HTMLElement).focus();
    }
  };

  // Navigate to the appropriate jurisdiction URL
  const navigateToJurisdiction = (jurisdiction: Jurisdiction) => {
    window.location.href = `https://${jurisdiction.domain}/`;
  };

  const handleKeyDown = (event: KeyboardEvent) => {
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
        activeIndex.value = (activeIndex.value + 1) % jurisdictions.value.length;
        focusActiveItem();
        break;
      case 'ArrowUp':
        event.preventDefault();
        activeIndex.value = (activeIndex.value - 1 + jurisdictions.value.length) % jurisdictions.value.length;
        focusActiveItem();
        break;
      case 'Home':
        event.preventDefault();
        activeIndex.value = 0;
        focusActiveItem();
        break;
      case 'End':
        event.preventDefault();
        activeIndex.value = jurisdictions.value.length - 1;
        focusActiveItem();
        break;
      case 'Enter':
      case ' ':
        // Critical fix: activate the option when Enter or Space is pressed
        event.preventDefault();
        navigateToJurisdiction(jurisdictions.value[activeIndex.value]);
        break;
    }
  };

  // Handle option item activation via keyboard or click
  const handleOptionActivation = (jurisdiction: Jurisdiction, index: number) => {
    activeIndex.value = index;
    navigateToJurisdiction(jurisdiction);
  };

  useClickOutside(dropdownRef, closeDropdown);

  // Safety functions for icon props
  const getIconCollection = (jurisdiction: Jurisdiction | null): string => jurisdiction?.icon?.collection || 'fa6-solid';

  const getIconName = (jurisdiction: Jurisdiction | null): string => jurisdiction?.icon?.name || 'globe';
</script>

<template>
  <div v-if="currentJurisdiction"
       ref="dropdownRef"
       class="relative inline-flex">
    <button @click="toggleDropdown"
            @keydown="handleKeyDown"
            class="group inline-flex items-center space-x-2 rounded-full
                  bg-inherit
                  px-3 py-1 text-sm font-medium
                  text-gray-700 dark:text-gray-400
                  hover:bg-gray-200 dark:hover:bg-gray-700
                  hover:text-gray-900 dark:hover:text-gray-300
                  shadow-sm hover:shadow-md
                  focus:outline-none focus:ring-2 focus:ring-brand-500
                  focus:ring-offset-2 focus:ring-offset-white
                  dark:focus:ring-brand-400 dark:focus:ring-offset-gray-900"
            :aria-expanded="isOpen"
            aria-haspopup="listbox"
            :aria-labelledby="'jurisdiction-label'"
            :id="'jurisdiction-button'">
      <OIcon :collection="getIconCollection(currentJurisdiction)"
             :name="getIconName(currentJurisdiction)"
             class="size-5 group-hover:text-brand-500 dark:group-hover:text-brand-400"
             aria-hidden="true" />

      <span class="whitespace-nowrap" id="jurisdiction-label">{{ currentJurisdiction.display_name }}</span>

      <svg xmlns="http://www.w3.org/2000/svg"
           class="size-4 -rotate-90"
           viewBox="0 0 20 20"
           fill="currentColor"
           aria-hidden="true">
        <path fill-rule="evenodd"
              d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
              clip-rule="evenodd" />
      </svg>
    </button>

    <transition enter-active-class="transition ease-out duration-100"
                enter-from-class="transform opacity-0 scale-95"
                enter-to-class="transform opacity-100 scale-100"
                leave-active-class="transition ease-in duration-75"
                leave-from-class="transform opacity-100 scale-100"
                leave-to-class="transform opacity-0 scale-95">
      <ul v-if="isOpen"
          ref="listboxRef"
          class="absolute bottom-full left-0 z-50 mb-1 max-h-60 min-w-[200px] w-max max-w-xs
                overflow-auto rounded-md bg-white py-1 text-base shadow-lg
                ring-1 ring-black ring-opacity-5 focus:outline-none
                dark:bg-gray-700 sm:text-sm"
          role="listbox"
          :aria-labelledby="'jurisdiction-label'"
          id="jurisdiction-listbox"
          @keydown="handleKeyDown">
        <li
            class="px-3 py-2 font-brand text-xs font-semibold uppercase tracking-wider text-gray-700 dark:text-gray-100">
          {{ $t('regions') }}
        </li>

        <li v-for="(jurisdiction, index) in jurisdictions"
            :key="jurisdiction.identifier"
            class="relative cursor-pointer select-none py-2 pl-3 pr-9 font-brand text-base
                 text-gray-700 transition-colors duration-200
                 hover:bg-brand-100 dark:text-gray-50 dark:hover:bg-brandcompdim-800"
            :class="{ 'bg-brand-50 dark:bg-brandcompdim-900': currentJurisdiction?.identifier === jurisdiction.identifier }"
            role="option"
            tabindex="0"
            :aria-selected="currentJurisdiction?.identifier === jurisdiction.identifier"
            :id="`jurisdiction-option-${index}`"
            @click="handleOptionActivation(jurisdiction, index)"
            @keydown.enter.prevent="handleOptionActivation(jurisdiction, index)"
            @keydown.space.prevent="handleOptionActivation(jurisdiction, index)">
            <span class="flex items-center">
              <OIcon :collection="getIconCollection(jurisdiction)"
                     :name="getIconName(jurisdiction)"
                     class="mr-2 size-5"
                     aria-hidden="true" />

              <span class="block truncate"
                    :class="{ 'font-semibold': currentJurisdiction?.identifier === jurisdiction.identifier }">
                {{ jurisdiction.display_name }}
              </span>
            </span>

            <span v-if="currentJurisdiction?.identifier === jurisdiction.identifier"
                  class="absolute inset-y-0 right-0 flex items-center pr-4">
              <OIcon
                collection="heroicons"
                name="check-20-solid"
                class="size-5 text-brand-600"
                aria-hidden="true" />
            </span>
        </li>
      </ul>
    </transition>
  </div>
</template>
