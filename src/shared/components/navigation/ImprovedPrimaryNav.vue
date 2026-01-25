<!-- src/shared/components/navigation/ImprovedPrimaryNav.vue -->

<!--
  Improved Primary Navigation Component

  Key improvements:
  - Tab navigation temporarily hidden (redesign pending)
  - Quick actions area for future features
  - Cleaner visual hierarchy
  - Room for growth without clutter

  Note: Domain scope switcher moved to OrganizationContextBar
-->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
</script>

<template>
  <nav
    class="flex items-center justify-between py-2"
    :aria-label="t('web.layout.main_navigation')">
    <!-- Left side: Reserved for future navigation items -->
    <div class="flex items-center">
      <!-- Future: Tab navigation, breadcrumbs, etc. -->
    </div>

    <!-- Right side: Reserved for future quick actions -->
    <div class="flex items-center gap-3">
      <!-- Future: Quick action buttons, search bar, etc. -->
    </div>
  </nav>
</template>
