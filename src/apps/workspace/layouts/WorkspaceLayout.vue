<!-- src/apps/workspace/layouts/WorkspaceLayout.vue -->

<!--
  Workspace Layout for authenticated users.

  ## Header Design Rationale (2026-01)

  Problem: The original two-row header had inverted visual hierarchy.
  - Logo (64-80px) dominated despite being low-value after first glance
  - Org/domain switchers were visually subordinate despite high interaction frequency
  - User menu truncated emails aggressively (double truncation: JS + CSS)
  - Identity (user menu) and context (org/domain) were split across rows

  Approach: Single-row merge prioritizing information scent over branding.
  - Compressed logo to ~36px for authenticated users
  - Org/domain switchers share the row with increased visual weight
  - User menu width expanded to accommodate typical email lengths
  - Related concepts (identity + workspace context) now grouped together

  Tradeoffs accepted:
  - Reduced brand presence for authenticated users (acceptable: they know where they are)
  - Horizontal space pressure on narrow viewports (mitigated via responsive breakpoints)
  - Different header experience logged-in vs logged-out (intentional: different needs)

  What we didn't fully solve:
  - Mobile still requires compromises; switchers collapse to icons at small widths
  - The logo size reduction may feel abrupt on auth state transitions
-->

<script setup lang="ts">
  import OrganizationContextBar from '@/apps/workspace/components/navigation/OrganizationContextBar.vue';
  import WorkspaceFooter from '@/apps/workspace/components/layout/WorkspaceFooter.vue';
  import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
  import TestModeBanner from '@/shared/components/ui/TestModeBanner.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useDomainsStore, useReceiptListStore } from '@/shared/stores';
  import { useTestPlanMode } from '@/shared/composables/useTestPlanMode';
  import type { ImprovedLayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';

  import BaseLayout from '@/shared/layouts/BaseLayout.vue';

  const props = withDefaults(defineProps<ImprovedLayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayMasthead: true,
    displayNavigation: true,
    displayPrimaryNav: false,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
    showSidebar: false,
    sidebarPosition: 'right',
  });

  // Store instances for centralized data loading
  const receiptListStore = useReceiptListStore();
  const domainsStore = useDomainsStore();
  const bootstrapStore = useBootstrapStore();
  const { domains_enabled } = storeToRefs(bootstrapStore);

  // Test plan mode composable
  const { isTestModeActive } = useTestPlanMode();

  // Centralize store refreshing to avoid duplicate API calls from header and footer
  onMounted(() => {
    receiptListStore.refreshRecords(true);
    if (domains_enabled.value) {
      domainsStore.refreshRecords(true);
    }
  });

  // Filter out sidebar-specific props for child components that don't need them
  const layoutProps = computed(() => {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { showSidebar, sidebarPosition, ...rest } = props;
    return rest;
  });
</script>

<template>
  <BaseLayout v-bind="layoutProps">
    <template #header>
      <ManagementHeader v-bind="layoutProps">
        <OrganizationContextBar />
      </ManagementHeader>
      <TestModeBanner v-if="isTestModeActive" />
    </template>

    <template #main>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="container mx-auto min-w-[320px] max-w-4xl px-4 py-8">
          <div class="flex items-start gap-8">
            <!-- Sidebar (Left position) -->
            <aside
              v-if="showSidebar && sidebarPosition === 'left'"
              class="hidden w-80 shrink-0 md:block">
              <slot name="sidebar-left">
                <!-- Default sidebar content can go here -->
              </slot>
            </aside>

            <!-- Main Content Area -->
            <main class="min-w-0 flex-1">
              <slot></slot>

              <!-- Mobile Quick Stats - Show below main content on small screens -->
              <div v-if="showSidebar && sidebarPosition === 'right'" class="mt-8 md:hidden">
                <div class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-800">
                  <h3 class="mb-3 text-sm font-semibold text-gray-900 dark:text-white">
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
              </div>
            </main>

            <!-- Sidebar (Right position) - Desktop only -->
            <aside
              v-if="showSidebar && sidebarPosition === 'right'"
              class="hidden w-80 shrink-0 md:block">
              <slot name="sidebar-right">
                <div class="space-y-6">
                  <!-- Quick Stats Card -->
                  <div class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-800">
                    <h3 class="mb-3 text-sm font-semibold text-gray-900 dark:text-white">
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
                  <div class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-800">
                    <h3 class="mb-3 text-sm font-semibold text-gray-900 dark:text-white">
                      Quick Actions
                    </h3>
                    <slot name="quick-actions">
                      <div class="space-y-2">
                        <router-link
                          to="/"
                          class="block w-full rounded-lg bg-brand-500 px-3 py-2 text-center
                                 text-sm font-medium text-white
                                 transition-colors hover:bg-brand-600">
                          Create New Secret
                        </router-link>
                        <router-link
                          to="/account/settings/api"
                          class="block w-full rounded-lg border border-gray-300 px-3 py-2
                                 text-center text-sm font-medium transition-colors
                                 hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700">
                          Generate API Key
                        </router-link>
                      </div>
                    </slot>
                  </div>

                  <!-- Help & Resources -->
                  <div class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-800">
                    <h3 class="mb-3 text-sm font-semibold text-gray-900 dark:text-white">
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
      <WorkspaceFooter v-bind="layoutProps" />
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
