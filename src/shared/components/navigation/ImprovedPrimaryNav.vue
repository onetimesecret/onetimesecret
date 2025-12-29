<!-- src/shared/components/navigation/ImprovedPrimaryNav.vue -->

<!--
  Improved Primary Navigation Component

  Key improvements:
  - Domain scope switcher on far left for context awareness
  - Tab navigation temporarily hidden (redesign pending)
  - Quick actions area for future features
  - Cleaner visual hierarchy
  - Room for growth without clutter
-->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DomainScopeSwitcher from '@/shared/components/navigation/DomainScopeSwitcher.vue';

  const { t } = useI18n();
</script>

<template>
  <nav
    class="flex items-center justify-between py-2"
    :aria-label="t('web.layout.main_navigation')">
    <!-- Left side: Domain Scope Switcher (far left per mockup) -->
    <div class="flex items-center">
      <DomainScopeSwitcher />
    </div>

    <!-- Right side: Reserved for future quick actions -->
    <div class="flex items-center gap-3">
      <!-- Future: Quick action buttons, search bar, etc. -->
    </div>
  </nav>
</template>
