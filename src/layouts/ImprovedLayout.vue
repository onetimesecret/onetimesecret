<!-- src/layouts/ImprovedLayout.vue -->
<!--
  Improved Layout with Optional Sidebar

  Key improvements:
  - Constrained main content width (900-1000px) for readability
  - Optional sidebar for metadata and ambient information
  - Better use of screen real estate
  - GitHub-inspired information hierarchy
-->

<script setup lang="ts">
  import ImprovedFooter from '@/components/layout/ImprovedFooter.vue';
  import ImprovedHeader from '@/components/layout/ImprovedHeader.vue';
  import type { LayoutProps } from '@/types/ui/layouts';
  import BaseLayout from './BaseLayout.vue';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';

  interface ImprovedLayoutProps extends LayoutProps {
    showSidebar?: boolean;
    sidebarPosition?: 'left' | 'right';
  }

  const props = withDefaults(defineProps<ImprovedLayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayMasthead: true,
    displayNavigation: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
    showSidebar: false,
    sidebarPosition: 'right',
  });

  const route = useRoute();

  // Determine if sidebar should show based on route
  const shouldShowSidebar = computed(() => {
    // Show sidebar on dashboard, recent, and account pages
    const sidebarRoutes = ['/dashboard', '/recent', '/domains', '/account'];
    return props.showSidebar && sidebarRoutes.some(r => route.path.startsWith(r));
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <ImprovedHeader v-bind="props" />
    </template>

    <template #main>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="container mx-auto min-w-[320px] max-w-4xl px-4 py-8">
          <div class="flex gap-8">
            <!-- Sidebar (Left position) -->
            <aside
              v-if="shouldShowSidebar && sidebarPosition === 'left'"
              class="hidden lg:block w-64 shrink-0">
              <slot name="sidebar-left">
                <!-- Default sidebar content can go here -->
              </slot>
            </aside>

            <!-- Main Content Area -->
            <main class="flex-1 min-w-0">
              <div class="bg-white dark:bg-inherit rounded-lg shadow-sm">
                <slot></slot>
              </div>
            </main>

            <!-- Sidebar (Right position) -->
            <aside
              v-if="shouldShowSidebar && sidebarPosition === 'right'"
              class="hidden lg:block w-80 shrink-0">
              <slot name="sidebar-right">
                <div class="space-y-6">
                  <!-- Quick Stats Card -->
                  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
                    <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">
                      Quick Stats
                    </h3>
                    <slot name="quick-stats">
                      <div class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                        <div class="flex justify-between">
                          <span>Active Secrets</span>
                          <span class="font-medium">--</span>
                        </div>
                        <div class="flex justify-between">
                          <span>Total Shared</span>
                          <span class="font-medium">--</span>
                        </div>
                        <div class="flex justify-between">
                          <span>Storage Used</span>
                          <span class="font-medium">--</span>
                        </div>
                      </div>
                    </slot>
                  </div>

                  <!-- Quick Actions Card -->
                  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
                    <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">
                      Quick Actions
                    </h3>
                    <slot name="quick-actions">
                      <div class="space-y-2">
                        <router-link
                          to="/"
                          class="block w-full px-3 py-2 text-sm text-center font-medium
                                 bg-brand-500 text-white rounded-lg
                                 hover:bg-brand-600 transition-colors">
                          Create New Secret
                        </router-link>
                        <router-link
                          to="/account/settings/api"
                          class="block w-full px-3 py-2 text-sm text-center font-medium
                                 border border-gray-300 dark:border-gray-600 rounded-lg
                                 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors">
                          Generate API Key
                        </router-link>
                      </div>
                    </slot>
                  </div>

                  <!-- Help & Resources -->
                  <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-4">
                    <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">
                      Resources
                    </h3>
                    <slot name="resources">
                      <ul class="space-y-2 text-sm">
                        <li>
                          <a href="/docs" class="text-brand-600 hover:text-brand-700 dark:text-brand-400">
                            Documentation
                          </a>
                        </li>
                        <li>
                          <a href="/api" class="text-brand-600 hover:text-brand-700 dark:text-brand-400">
                            API Reference
                          </a>
                        </li>
                        <li>
                          <a href="/support" class="text-brand-600 hover:text-brand-700 dark:text-brand-400">
                            Get Support
                          </a>
                        </li>
                      </ul>
                    </slot>
                  </div>
                </div>
              </slot>
            </aside>
          </div>
        </div>
      </div>
    </template>

    <template #footer>
      <ImprovedFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>

<style scoped>
/* Responsive adjustments */
@media (max-width: 1024px) {
  main {
    max-width: 100%;
  }
}
</style>
