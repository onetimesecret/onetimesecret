<!-- src/components/icons/logos/OnetimeSecret.vue -->

<script setup lang="ts">
  import { onKeyStroke, useEventListener } from '@vueuse/core';
  import { computed, nextTick, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  import OIcon from '@/components/icons/OIcon.vue';
  import type { Jurisdiction } from '@/schemas/models/jurisdiction';
  import { useJurisdictionStore } from '@/stores/jurisdictionStore';
  import type { LogoConfig } from '@/types/ui/layouts';
  import OnetimeSecretIcon from './OnetimeSecretIcon.vue';

  /**
   * Props for controlling logo appearance
   */
  const props = withDefaults(defineProps<LogoConfig>(), {
    size: 64,
    mode: 'light',
    href: '/',
    showCompanyName: true,
  });

  const { t } = useI18n();

  // Core logo properties
  const ariaLabel = computed(() => props.ariaLabel || t('one-time-secret-literal'));
  const companyName = computed(() => props.companyName || t('one-time-secret-literal'));
  const textColor = computed(() => (props.mode === 'dark' ? 'text-white' : 'text-gray-800'));
  const svgSize = computed(() =>
    typeof props.size === 'number' && props.size > 0 ? props.size : 64
  );

  // Jurisdiction store and selection handling
  const jurisdictionStore = useJurisdictionStore();
  const currentJurisdiction = computed<Jurisdiction | null>(
    () => jurisdictionStore.getCurrentJurisdiction
  );

  // Jurisdiction icon helper functions
  const getIconCollection = (jurisdiction: Jurisdiction | null): string => {
    return jurisdiction?.icon?.collection || 'fa6-solid';
  };

  const getIconName = (jurisdiction: Jurisdiction | null): string => {
    return jurisdiction?.icon?.name || 'globe';
  };

  // Jurisdiction menu state and handlers
  const tooltipVisible = ref(false);
  const menuRef = ref<HTMLElement | null>(null);
  const buttonRef = ref<HTMLElement | null>(null);

  const navigateToJurisdiction = (domain: string) => {
    window.location.href = `https://${domain}/`;
  };

  const toggleJurisdictionMenu = () => {
    tooltipVisible.value = !tooltipVisible.value;
  };

  const closeJurisdictionMenu = () => {
    tooltipVisible.value = false;
    document.getElementById('jurisdiction-button')?.focus();
  };

  // Keyboard event handlers
  const handleJurisdictionKeydown = (event: KeyboardEvent) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggleJurisdictionMenu();
    } else if (event.key === 'Escape' && tooltipVisible.value) {
      event.preventDefault();
      tooltipVisible.value = false;
    }
  };

  // Enhanced keyboard handling using VueUse
  onKeyStroke('Escape', (e) => {
    if (tooltipVisible.value) {
      e.preventDefault();
      closeJurisdictionMenu();
    }
  });

  // Click outside handling
  useEventListener(document, 'mousedown', (event) => {
    if (
      tooltipVisible.value &&
      menuRef.value &&
      buttonRef.value &&
      !menuRef.value.contains(event.target as Node) &&
      !buttonRef.value.contains(event.target as Node)
    ) {
      tooltipVisible.value = false;
    }
  });

  // Add keyboard navigation within dropdown
  watch(tooltipVisible, (newValue) => {
    if (newValue) {
      // Focus first option when menu opens
      nextTick(() => {
        const firstOption = document.getElementById('jurisdiction-option-0');
        if (firstOption) firstOption.focus();
      });
    }
  });
</script>

<template>
  <div
    class="flex items-center gap-3"
    :aria-label="ariaLabel">
    <div class="relative">
      <!-- Logomark -->
      <a
        :href="props.href"
        :alt="ariaLabel"
        class="">
        <OnetimeSecretIcon
          :size="svgSize"
          :aria-label="ariaLabel"
          class="shrink-0 rounded-lg"
          :style="{ width: `${svgSize}px`, height: `${svgSize}px` }"
      /></a>

      <!-- Jurisdiction selector button -->
      <div
        v-if="jurisdictionStore.enabled"
        class="relative">
        <!-- prettier-ignore-attribute class -->
        <button
          id="jurisdiction-button"
          ref="buttonRef"
          aria-haspopup="listbox"
          :aria-expanded="tooltipVisible"
          aria-controls="jurisdiction-menu"
          class="absolute -bottom-0.5 -right-0.5 z-10 rounded border border-brand-100
                 bg-brand-500 px-0.5 py-0 font-brand
                 text-[0.6em] font-medium text-brand-100
                 dark:border-slate-800 dark:bg-slate-800 dark:text-slate-100"
          @click="toggleJurisdictionMenu"
          @keydown="handleJurisdictionKeydown">
          {{ currentJurisdiction?.identifier }}
        </button>

        <!-- Jurisdiction dropdown menu -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-show="tooltipVisible"
          id="jurisdiction-menu"
          ref="menuRef"
          role="listbox"
          :aria-labelledby="'jurisdiction-button'"
          tabindex="-1"
          class="absolute z-50 mt-1 w-max min-w-[200px]
                 divide-y divide-gray-200 rounded-lg bg-white px-2 py-1
                 text-xs shadow-lg ring-1 ring-black/5
                 dark:divide-gray-700 dark:bg-gray-800">
          <div class="py-2">
            <!-- prettier-ignore-attribute class -->
            <div
              class="px-3 py-2 font-brand text-xs uppercase
                  tracking-wider text-gray-700 dark:text-gray-100">
              {{ t('regions') }}
            </div>
            <!-- prettier-ignore-attribute class -->
            <div
              v-for="(jurisdiction, index) in jurisdictionStore.jurisdictions"
              :key="jurisdiction.identifier"
              :id="`jurisdiction-option-${index}`"
              role="option"
              :aria-selected="currentJurisdiction?.identifier === jurisdiction.identifier"
              tabindex="0"
              class="group flex w-full cursor-pointer items-center rounded-md p-2 text-sm
                       text-gray-700 hover:bg-gray-100
                       dark:text-gray-300 dark:hover:bg-gray-700"
              @click="navigateToJurisdiction(jurisdiction.domain)"
              @keydown.enter="navigateToJurisdiction(jurisdiction.domain)"
              @keydown.space.prevent="navigateToJurisdiction(jurisdiction.domain)">
              <span class="flex items-center font-brand">
                <OIcon
                  :collection="getIconCollection(jurisdiction)"
                  :name="getIconName(jurisdiction)"
                  class="mr-2 size-5"
                  aria-hidden="true" />
                <span
                  class="block truncate"
                  :class="{
                    'font-bold': currentJurisdiction?.identifier === jurisdiction.identifier,
                  }">
                  {{ jurisdiction.display_name }}
                </span>
              </span>
              <span
                v-if="currentJurisdiction?.identifier === jurisdiction.identifier"
                class="ml-auto text-brand-500">
                <svg
                  class="size-5"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true">
                  <path
                    fill-rule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clip-rule="evenodd" />
                </svg>
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Text content -->
    <div
      v-if="props.showCompanyName && companyName"
      class="flex flex-col">
        <a
          :href="props.href"
          :alt="ariaLabel"
          class="">
        <div :class="[textColor, 'text-lg font-bold leading-tight']">
          {{ companyName }}
        </div>
        <!-- Tagline -->
        <div
          class="text-xs text-gray-500 dark:text-gray-400"
          aria-hidden="true">
          {{ t('tagline-signed') }}.
          <em>{{ t('tagline-sealed') }}. </em>
          <span class="group/tooltip relative inline-block">
            {{ t('tagline-delivered') }}.<sup
              class="text-[0.7em] text-gray-500 [animation:pulse_4s_ease-in-out_infinite] group-hover/tooltip:[animation:none] dark:text-gray-400"
              >*</sup
            >
            <span
              class="absolute left-full top-0 ml-1 hidden w-max rounded bg-gray-200/80 px-2 py-1 text-xs text-gray-500 group-hover/tooltip:block dark:bg-gray-800/80 dark:text-gray-400">
              <sup class="text-[0.7em] text-gray-500 dark:text-gray-400">*</sup>
              {{ t('recipient-delivery-is-optional') }}
            </span>
          </span>
        </div>
          </a>
    </div>
  </div>
</template>
