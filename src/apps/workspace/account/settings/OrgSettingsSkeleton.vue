<!-- src/apps/workspace/account/settings/OrgSettingsSkeleton.vue -->

<script setup lang="ts">
  /**
   * OrgSettingsSkeleton
   *
   * Page-specific loading placeholder for OrganizationSettings.vue. Co-located
   * with the view (mirrors how DashboardSkeleton lives beside the dashboard).
   *
   * Where SettingsSkeleton is generic field-group chrome, this one reproduces
   * the geometry unique to this page: the two-part page header (back-arrow +
   * truncated title on the left, a pill-shaped billing chip on the right) and
   * the underlined tab bar. Below that it shows a single content panel whose
   * body mirrors the general/settings-tab field shape — so the comparison
   * against SettingsSkeleton is apples-to-apples on the body and isolates the
   * header + tab bar as the thing only the page-specific skeleton captures.
   *
   * Geometry is hardcoded to this one view; it is intentionally not prop-driven.
   *
   * Note on fidelity: the live page hides the tab bar while loading
   * (it is gated on the fetched `organization`), so the real on-screen load is
   * just header + spinner. This skeleton previews the *loaded* chrome instead —
   * the point of a layout-aware skeleton is to reserve the post-load shape.
   */
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="mx-auto max-w-4xl animate-pulse space-y-6 px-4 py-8 motion-reduce:animate-none sm:px-6 lg:px-8">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>

    <!-- Page header: back-arrow + title (left), billing chip (right) -->
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-2">
        <!-- Back arrow -->
        <Skeleton
          width="w-5"
          height="h-5"
          :pulse="false" />
        <!-- Org title -->
        <Skeleton
          width="w-48"
          height="h-6"
          :pulse="false" />
      </div>
      <!-- Billing/plan chip (pill) -->
      <Skeleton
        width="w-24"
        height="h-7"
        rounded="rounded-full"
        :pulse="false" />
    </div>

    <!-- Tab bar (underlined nav): a row of tab-label blocks above the border -->
    <div class="flex space-x-8 border-b border-gray-200 pb-4 dark:border-gray-700">
      <Skeleton
        class="w-16"
        height="h-4"
        :pulse="false" />
      <Skeleton
        class="w-16"
        height="h-4"
        :pulse="false" />
      <Skeleton
        class="w-16"
        height="h-4"
        :pulse="false" />
    </div>

    <!-- Content panel: section header (title + subtitle) over a field body -->
    <div class="rounded-lg border border-gray-200/60 dark:border-gray-700/60">
      <!-- Panel header -->
      <div class="space-y-2 border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <Skeleton
          width="w-40"
          height="h-5"
          :pulse="false" />
        <Skeleton
          width="w-2/3"
          height="h-3"
          :pulse="false" />
      </div>

      <!-- Panel body: label + input field groups -->
      <div class="space-y-6 p-6">
        <div
          v-for="n in 2"
          :key="n"
          class="space-y-2">
          <Skeleton
            width="w-1/4"
            height="h-4"
            :pulse="false" />
          <Skeleton
            height="h-10"
            rounded="rounded-md"
            :pulse="false" />
        </div>
      </div>
    </div>
  </div>
</template>
