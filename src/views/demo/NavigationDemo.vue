<!-- src/views/demo/NavigationDemo.vue -->
<!--
  Navigation Demo Page

  This page demonstrates the improved navigation and layout system.
  It can be accessed at /demo/navigation to preview the changes.
-->

<script setup lang="ts">
import { ref, provide } from 'vue';

const showSidebar = ref(true);
const sidebarPosition = ref<'left' | 'right'>('right');

const toggleSidebar = () => {
  showSidebar.value = !showSidebar.value;
};

const toggleSidebarPosition = () => {
  sidebarPosition.value = sidebarPosition.value === 'right' ? 'left' : 'right';
};

// Provide these values so they can be consumed by parent layout if needed
provide('demoShowSidebar', showSidebar);
provide('demoSidebarPosition', sidebarPosition);
</script>

<template>
  <div class="p-6">
    <div class="mb-8">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">
        Navigation & Layout Improvements Demo
      </h1>
      <p class="text-gray-600 dark:text-gray-400">
        Preview of the improved navigation system inspired by GitHub's information architecture
      </p>
    </div>

    <!-- Controls -->
    <div class="mb-8 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
      <h2 class="text-lg font-semibold mb-4">Layout Controls</h2>
      <div class="flex flex-wrap gap-4">
        <button
          @click="toggleSidebar"
          class="px-4 py-2 bg-white dark:bg-gray-800 rounded-lg shadow-sm
                 hover:shadow-md transition-shadow">
          {{ showSidebar ? 'Hide' : 'Show' }} Sidebar
        </button>
        <button
          @click="toggleSidebarPosition"
          :disabled="!showSidebar"
          class="px-4 py-2 bg-white dark:bg-gray-800 rounded-lg shadow-sm
                 hover:shadow-md transition-shadow disabled:opacity-50">
          Sidebar Position: {{ sidebarPosition }}
        </button>
      </div>
    </div>

    <!-- Live Demo Container -->
    <div class="mb-8 border-2 border-gray-300 dark:border-gray-600 rounded-lg overflow-hidden">
      <div class="bg-gray-100 dark:bg-gray-800 px-4 py-2 border-b border-gray-300 dark:border-gray-600">
        <span class="text-sm font-medium">Live Preview</span>
      </div>
      <div class="bg-gray-50 dark:bg-gray-900 p-4">
        <div class="flex gap-6">
          <!-- Sidebar (Left position) -->
          <aside
            v-if="showSidebar && sidebarPosition === 'left'"
            class="w-64 shrink-0 space-y-4 transition-all duration-300">
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
              <h3 class="text-sm font-semibold mb-3">Quick Stats</h3>
              <div class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                <div class="flex justify-between">
                  <span>Active Secrets</span>
                  <span class="font-medium">12</span>
                </div>
                <div class="flex justify-between">
                  <span>Total Shared</span>
                  <span class="font-medium">847</span>
                </div>
              </div>
            </div>
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
              <h3 class="text-sm font-semibold mb-3">Quick Actions</h3>
              <button class="w-full px-3 py-2 bg-brand-500 text-white text-sm rounded">
                Create New Secret
              </button>
            </div>
          </aside>

          <!-- Main Content -->
          <div class="flex-1 bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
            <h2 class="text-lg font-semibold mb-4">Main Content Area</h2>
            <p class="text-gray-600 dark:text-gray-400 mb-4">
              This demonstrates the constrained content width with optional sidebar.
              The sidebar provides persistent context without interrupting the main flow.
            </p>
            <div class="grid grid-cols-2 gap-4">
              <div class="bg-gray-100 dark:bg-gray-700 rounded p-3">
                <div class="h-16 bg-gray-300 dark:bg-gray-600 rounded mb-2"></div>
                <div class="h-2 bg-gray-300 dark:bg-gray-600 rounded w-3/4"></div>
              </div>
              <div class="bg-gray-100 dark:bg-gray-700 rounded p-3">
                <div class="h-16 bg-gray-300 dark:bg-gray-600 rounded mb-2"></div>
                <div class="h-2 bg-gray-300 dark:bg-gray-600 rounded w-2/3"></div>
              </div>
            </div>
          </div>

          <!-- Sidebar (Right position) -->
          <aside
            v-if="showSidebar && sidebarPosition === 'right'"
            class="w-64 shrink-0 space-y-4 transition-all duration-300">
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
              <h3 class="text-sm font-semibold mb-3">Quick Stats</h3>
              <div class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                <div class="flex justify-between">
                  <span>Active Secrets</span>
                  <span class="font-medium">12</span>
                </div>
                <div class="flex justify-between">
                  <span>Total Shared</span>
                  <span class="font-medium">847</span>
                </div>
              </div>
            </div>
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
              <h3 class="text-sm font-semibold mb-3">Quick Actions</h3>
              <button class="w-full px-3 py-2 bg-brand-500 text-white text-sm rounded">
                Create New Secret
              </button>
            </div>
          </aside>
        </div>
      </div>
    </div>

    <!-- Key Improvements -->
    <div class="grid md:grid-cols-2 gap-6 mb-8">
      <div class="bg-green-50 dark:bg-green-900/20 rounded-lg p-4">
        <h3 class="font-semibold text-green-900 dark:text-green-100 mb-2">
          ✅ What's Better
        </h3>
        <ul class="space-y-1 text-sm text-green-800 dark:text-green-200">
          <li>• Wider header container (max-w-6xl)</li>
          <li>• Horizontal tab navigation</li>
          <li>• Quick action buttons</li>
          <li>• Sidebar for ambient information</li>
          <li>• Constrained content width for readability</li>
          <li>• Clear visual hierarchy</li>
          <li>• Room for feature growth</li>
          <li>• Better use of screen space</li>
        </ul>
      </div>

      <div class="bg-amber-50 dark:bg-amber-900/20 rounded-lg p-4">
        <h3 class="font-semibold text-amber-900 dark:text-amber-100 mb-2">
          🎯 Design Principles
        </h3>
        <ul class="space-y-1 text-sm text-amber-800 dark:text-amber-200">
          <li>• Information density without visual density</li>
          <li>• Progressive disclosure of features</li>
          <li>• Persistent context via sidebar</li>
          <li>• Primary/secondary action hierarchy</li>
          <li>• Scannable vertical lists</li>
          <li>• Ambient awareness of stats</li>
          <li>• Consistent spacing patterns</li>
          <li>• Mobile-first responsive design</li>
        </ul>
      </div>
    </div>


    <!-- Implementation Notes -->
    <div class="mt-8 p-4 bg-gray-100 dark:bg-gray-800 rounded-lg">
      <h3 class="font-semibold mb-2">Implementation Notes</h3>
      <ul class="text-sm text-gray-600 dark:text-gray-400 space-y-1">
        <li>• Components: ImprovedHeader.vue, ImprovedPrimaryNav.vue, ImprovedLayout.vue</li>
        <li>• Backward compatible with existing views</li>
        <li>• Progressive enhancement approach</li>
        <li>• Can be adopted incrementally per route</li>
        <li>• Maintains existing Tailwind design system</li>
      </ul>
    </div>
  </div>
</template>
