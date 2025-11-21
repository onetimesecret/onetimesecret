<!-- Redesign Mockup Index - Navigation Page -->
<script setup lang="ts">
import { ref } from 'vue';
import DefaultStateMockup from '@/components/mockups/redesign/DefaultStateMockup.vue';
import ActiveStateMockup from '@/components/mockups/redesign/ActiveStateMockup.vue';
import AdvancedExpandedMockup from '@/components/mockups/redesign/AdvancedExpandedMockup.vue';
import PreFlightModalMockup from '@/components/mockups/redesign/PreFlightModalMockup.vue';
import MobileViewMockup from '@/components/mockups/redesign/MobileViewMockup.vue';

type MockupView = 'overview' | 'default' | 'active' | 'advanced' | 'preflight' | 'mobile';

const currentView = ref<MockupView>('overview');

const mockups = [
  {
    id: 'default',
    title: 'Default State',
    description: 'Empty form, first impression',
    component: DefaultStateMockup,
    icon: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z',
  },
  {
    id: 'active',
    title: 'Active State',
    description: 'With content entered',
    component: ActiveStateMockup,
    icon: 'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z',
  },
  {
    id: 'advanced',
    title: 'Advanced Options',
    description: 'Expanded configuration',
    component: AdvancedExpandedMockup,
    icon: 'M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4',
  },
  {
    id: 'preflight',
    title: 'Pre-Flight Confirmation',
    description: 'Final review modal',
    component: PreFlightModalMockup,
    icon: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
  },
  {
    id: 'mobile',
    title: 'Mobile View',
    description: 'Responsive design',
    component: MobileViewMockup,
    icon: 'M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z',
  },
];

const setView = (view: MockupView) => {
  currentView.value = view;
  // Scroll to top when changing views
  window.scrollTo({ top: 0, behavior: 'smooth' });
};
</script>

<template>
  <div class="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-slate-950 dark:to-slate-900">
    <!-- Header -->
    <header class="border-b border-gray-200 bg-white/80 backdrop-blur-lg dark:border-gray-800 dark:bg-slate-900/80">
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
              OneTimeSecret Redesign
            </h1>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
              Static mockups for the create secret experience
            </p>
          </div>
          <button
            v-if="currentView !== 'overview'"
            @click="setView('overview')"
            class="rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-50 dark:border-gray-600 dark:bg-slate-800 dark:text-gray-300 dark:hover:bg-slate-700">
            ← Back to Overview
          </button>
        </div>
      </div>
    </header>

    <!-- Overview Grid -->
    <div v-if="currentView === 'overview'" class="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
      <!-- Design Philosophy -->
      <div class="mb-12 rounded-xl border border-blue-200 bg-blue-50 p-6 dark:border-blue-800 dark:bg-blue-900/20">
        <h2 class="mb-3 text-xl font-semibold text-blue-900 dark:text-blue-200">
          Design Philosophy: Progressive Simplicity
        </h2>
        <p class="mb-4 text-blue-800 dark:text-blue-300">
          Start with absolute minimum complexity, progressively reveal power features. The textarea is the hero—everything else supports the primary action of entering secret content.
        </p>
        <div class="grid gap-4 md:grid-cols-3">
          <div class="rounded-lg bg-white p-4 dark:bg-slate-800">
            <div class="mb-2 flex items-center gap-2">
              <svg class="size-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              <h3 class="font-semibold text-gray-900 dark:text-white">Speed</h3>
            </div>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              Power users complete flows in <10 seconds
            </p>
          </div>
          <div class="rounded-lg bg-white p-4 dark:bg-slate-800">
            <div class="mb-2 flex items-center gap-2">
              <svg class="size-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
              </svg>
              <h3 class="font-semibold text-gray-900 dark:text-white">Simplicity</h3>
            </div>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              30-40% cognitive load reduction
            </p>
          </div>
          <div class="rounded-lg bg-white p-4 dark:bg-slate-800">
            <div class="mb-2 flex items-center gap-2">
              <svg class="size-5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
              <h3 class="font-semibold text-gray-900 dark:text-white">Trust</h3>
            </div>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              Security measures always visible
            </p>
          </div>
        </div>
      </div>

      <!-- Mockup Cards -->
      <h2 class="mb-6 text-2xl font-semibold text-gray-900 dark:text-white">
        Explore Mockups
      </h2>
      <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        <button
          v-for="mockup in mockups"
          :key="mockup.id"
          @click="setView(mockup.id as MockupView)"
          class="group relative overflow-hidden rounded-xl border border-gray-200 bg-white p-6 text-left shadow-sm transition-all hover:border-blue-500 hover:shadow-lg dark:border-gray-700 dark:bg-slate-900 dark:hover:border-blue-500">
          <!-- Icon -->
          <div class="mb-4 inline-flex rounded-lg bg-gradient-to-br from-blue-500 to-blue-600 p-3 text-white shadow-lg group-hover:scale-110 group-hover:shadow-xl transition-transform">
            <svg class="size-6" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" :d="mockup.icon" />
            </svg>
          </div>

          <!-- Content -->
          <h3 class="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
            {{ mockup.title }}
          </h3>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            {{ mockup.description }}
          </p>

          <!-- Arrow -->
          <div class="absolute bottom-6 right-6 translate-x-2 opacity-0 transition-all group-hover:translate-x-0 group-hover:opacity-100">
            <svg class="size-5 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
            </svg>
          </div>
        </button>
      </div>

      <!-- Key Features -->
      <div class="mt-12 rounded-xl border border-gray-200 bg-white p-8 dark:border-gray-700 dark:bg-slate-900">
        <h2 class="mb-6 text-xl font-semibold text-gray-900 dark:text-white">
          Key Features
        </h2>
        <div class="grid gap-6 md:grid-cols-2">
          <div class="flex gap-4">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-green-100 dark:bg-green-900/20">
              <svg class="size-5 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <div>
              <h3 class="mb-1 font-semibold text-gray-900 dark:text-white">WCAG 2.1 AA Compliant</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                Screen reader optimized, keyboard navigation, proper ARIA labels
              </p>
            </div>
          </div>
          <div class="flex gap-4">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-blue-100 dark:bg-blue-900/20">
              <svg class="size-5 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <div>
              <h3 class="mb-1 font-semibold text-gray-900 dark:text-white">Core Web Vitals Optimized</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                INP <200ms, LCP <2.5s, CLS <0.1 for excellent performance
              </p>
            </div>
          </div>
          <div class="flex gap-4">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-purple-100 dark:bg-purple-900/20">
              <svg class="size-5 text-purple-600 dark:text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
              </svg>
            </div>
            <div>
              <h3 class="mb-1 font-semibold text-gray-900 dark:text-white">Mobile-First Design</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                One-handed operation, large touch targets (48x48px), responsive layout
              </p>
            </div>
          </div>
          <div class="flex gap-4">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-amber-100 dark:bg-amber-900/20">
              <svg class="size-5 text-amber-600 dark:text-amber-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
              </svg>
            </div>
            <div>
              <h3 class="mb-1 font-semibold text-gray-900 dark:text-white">Smart Suggestions</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                Context-aware recommendations based on content patterns (API keys, etc.)
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Mockup Display -->
    <div v-else>
      <component :is="mockups.find(m => m.id === currentView)?.component" />
    </div>
  </div>
</template>

<style scoped>
/* Additional styles for smooth transitions */
</style>
