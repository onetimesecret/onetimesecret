<!-- src/components/layout/Masthead.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import HeaderUserNav from '@/components/layout/HeaderUserNav.vue';
  import SettingsModal from '@/components/modals/SettingsModal.vue';
  import { useEventListener, onKeyStroke } from '@vueuse/core';
  import type { Jurisdiction } from '@/schemas/models/jurisdiction';
  import { WindowService } from '@/services/window.service';
  import { useJurisdictionStore } from '@/stores/jurisdictionStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, nextTick, ref, watch } from 'vue';

  withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  const windowProps = WindowService.getMultiple([
    'regions_enabled',
    'regions',
    'authentication',
    'authenticated',
    'cust',
  ]);

  const isColonel = computed(() => windowProps.cust?.role === 'colonel');

  // Reactive state
  const isSettingsModalOpen = ref(false);

  // Methods
  const openSettingsModal = () => {
    isSettingsModalOpen.value = true;
  };

  const closeSettingsModal = () => {
    isSettingsModalOpen.value = false;
  };
  const jurisdictionStore = useJurisdictionStore();
  const currentJurisdiction = computed<Jurisdiction | null>(
    () => jurisdictionStore.getCurrentJurisdiction
  );

  // Safety functions for icon props
  const getIconCollection = (jurisdiction: Jurisdiction | null): string => {
    return jurisdiction?.icon?.collection || 'fa6-solid';
  };

  const getIconName = (jurisdiction: Jurisdiction | null): string => {
    return jurisdiction?.icon?.name || 'globe';
  };

  const tooltipVisible = ref(false);
  const navigateToJurisdiction = (domain: string) => {
    window.location.href = `https://${domain}/`;
  };
  const toggleJurisdictionMenu = () => {
    tooltipVisible.value = !tooltipVisible.value;
  };

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

  // Focus management for dropdown
  const closeJurisdictionMenu = () => {
    tooltipVisible.value = false;
    document.getElementById('jurisdiction-button')?.focus();
  };

  // We can also simplify the click outside handling with VueUse
  const menuRef = ref<HTMLElement | null>(null);
  const buttonRef = ref<HTMLElement | null>(null);

  useEventListener(document, 'mousedown', (event) => {
    if (tooltipVisible.value &&
        menuRef.value &&
        buttonRef.value &&
        !menuRef.value.contains(event.target as Node) &&
        !buttonRef.value.contains(event.target as Node)) {
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
       class="w-full">
    <div class="flex flex-col items-center justify-between sm:flex-row">

      <div class="mb-4 flex items-center justify-between sm:mb-0">
        <div class="relative">
          <router-link to="/"
                       class="group flex items-center"
                       :aria-label="$t('onetime-secret-homepage')">
            <div class="relative">
              <img id="logo"
                   src="@/assets/img/onetime-logo-v3-xl.svg"
                   class="size-12 rounded-md transition-transform sm:size-16"
                   height="64"
                   width="64"
                   alt="" />
            </div>
          </router-link>
          <!-- Jurisdiction selector section -->
          <div v-if="jurisdictionStore.enabled"
               class="relative">
            <button id="jurisdiction-button"
                    ref="buttonRef"
                    aria-haspopup="listbox"
                    :aria-expanded="tooltipVisible"
                    aria-controls="jurisdiction-menu"
                    class="absolute -right-0.5 -bottom-0.5 rounded px-0.5 py-0 text-[0.6em]
                           font-brand font-medium bg-brand-500 text-brand-100
                           border border-brand-100 dark:border-slate-800
                           dark:bg-slate-800 dark:text-slate-100 z-10"
                    @click="toggleJurisdictionMenu"
                    @keydown="handleJurisdictionKeydown">
              {{ currentJurisdiction?.identifier }}
            </button>
            <div v-show="tooltipVisible"
                 id="jurisdiction-menu"
                 ref="menuRef"
                 role="listbox"
                 :aria-labelledby="'jurisdiction-button'"
                 tabindex="-1"
                 class="absolute z-50 mt-1 w-max min-w-[200px]
                           rounded-lg bg-white dark:bg-gray-800 px-2 py-1 text-xs
                           shadow-lg ring-1 ring-black ring-opacity-5
                           divide-y divide-gray-200 dark:divide-gray-700">
              <div class="py-2">
                <div class="px-3 py-2 font-brand text-xs uppercase
                                  tracking-wider text-gray-700 dark:text-gray-100">
                  {{ $t('regions') }}
                </div>
                <div v-for="(jurisdiction, index) in jurisdictionStore.jurisdictions"
                     :key="jurisdiction.identifier"
                     :id="`jurisdiction-option-${index}`"
                     role="option"
                     :aria-selected="currentJurisdiction?.identifier === jurisdiction.identifier"
                     tabindex="0"
                     class="group flex w-full items-center rounded-md px-2 py-2 text-sm
                               hover:bg-gray-100 dark:hover:bg-gray-700
                               text-gray-700 dark:text-gray-300
                               cursor-pointer"
                     @click="navigateToJurisdiction(jurisdiction.domain)"
                     @keydown.enter="navigateToJurisdiction(jurisdiction.domain)"
                     @keydown.space.prevent="navigateToJurisdiction(jurisdiction.domain)">
                  <span class="flex items-center font-brand">
                    <OIcon :collection="getIconCollection(jurisdiction)"
                           :name="getIconName(jurisdiction)"
                           class="mr-2 size-5"
                           aria-hidden="true" />
                    <span class="block truncate"
                          :class="{ 'font-bold': currentJurisdiction?.identifier === jurisdiction.identifier }">
                      {{ jurisdiction.display_name }}
                    </span>
                  </span>
                  <span v-if="currentJurisdiction?.identifier === jurisdiction.identifier"
                        class="ml-auto text-brand-500">
                    <svg class="size-5"
                         xmlns="http://www.w3.org/2000/svg"
                         viewBox="0 0 20 20"
                         fill="currentColor"
                         aria-hidden="true">
                      <path fill-rule="evenodd"
                            d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                            clip-rule="evenodd" />
                    </svg>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <router-link to="/">
          <div class="ml-3 flex flex-col">
            <span class="font-brand text-xl font-bold tracking-tight text-gray-900 dark:text-white">
              {{ $t('onetime-secret-literal') }}
            </span>
            <span class="text-xs text-gray-500 dark:text-gray-400">
              {{ $t('tagline-signed') }}.
              <em>{{ $t('tagline-sealed') }}. </em>
              <span class="group/tooltip relative inline-block">
                {{ $t('tagline-delivered') }}.<sup
                    class="text-[0.7em] text-gray-500 dark:text-gray-400 [animation:pulse_4s_ease-in-out_infinite] group-hover/tooltip:[animation:none]">*</sup>
                <span class="absolute left-full top-0 ml-1 hidden group-hover/tooltip:block
                              bg-gray-200/80 dark:bg-gray-800/80 text-gray-500 dark:text-gray-400
                              text-xs rounded py-1 px-2 w-max">
                  <sup class="text-[0.7em] text-gray-500 dark:text-gray-400">*</sup>
                  {{ $t('recipient-delivery-is-optional') }}
                </span>
              </span>
            </span>
          </div>
        </router-link>

      </div>

      <nav v-if="displayNavigation"
           role="navigation"
           :aria-label="$t('main-navigation')"
           class="flex flex-wrap items-center justify-center gap-4 font-brand text-sm sm:justify-end sm:text-base">
        <template v-if="windowProps.authenticated && windowProps.cust">
          <HeaderUserNav :cust="windowProps.cust"
                         :colonel="isColonel" />

          <button @click="openSettingsModal"
                  class="text-xl text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
                  :aria-label="$t('web.COMMON.header_settings')">
            <OIcon class="size-5"
                   collection="material-symbols"
                   name="settings-outline" />
          </button>

          <SettingsModal :is-open="isSettingsModalOpen"
                         @close="closeSettingsModal" />

          <span class="text-gray-400"
                role="separator">
            |
          </span>

          <router-link to="/logout"
                       class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
                       :title="$t('web.COMMON.header_logout')"
                       :aria-label="$t('web.COMMON.header_logout')">
            <OIcon class="size-5"
                   collection="heroicons"
                   name="arrow-right-on-rectangle-solid" />
          </router-link>
        </template>

        <template v-else>
          <template v-if="windowProps.authentication.enabled">
            <router-link v-if="windowProps.authentication.signup"
                         to="/signup"
                         :title="$t('signup-individual-and-business-plans')"
                         class="font-bold text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ $t('web.COMMON.header_create_account') }}
            </router-link>
            <span class="text-gray-400"
                  aria-hidden="true"
                  role="separator">
              |
            </span>
            <router-link to="/about"
                         :title="$t('about-onetime-secret')"
                         class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ $t('web.COMMON.header_about') }}
            </router-link>
            <span class="text-gray-400"
                  aria-hidden="true"
                  role="separator">
              |
            </span>
            <router-link v-if="windowProps.authentication.signin"
                         to="/signin"
                         :title="$t('log-in-to-onetime-secret')"
                         class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ $t('web.COMMON.header_sign_in') }}
            </router-link>
          </template>

          <router-link v-else
                       to="/about"
                       :title="$t('about-onetime-secret-0')"
                       class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ $t('web.COMMON.header_about') }}
          </router-link>
        </template>
      </nav>
    </div>
  </div>
</template>
