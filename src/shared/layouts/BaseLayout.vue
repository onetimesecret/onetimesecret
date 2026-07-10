<!-- src/shared/layouts/BaseLayout.vue -->

<script setup lang="ts">
  import GlobalBroadcast from '@/shared/components/ui/GlobalBroadcast.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { useTheme } from '@/shared/composables/useTheme';
  import { storeToRefs } from 'pinia';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { isColorValue } from '@/utils/color-utils';
  import { computed, onMounted } from 'vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    bannerAudience: 'public',
  });

  // Initialize theme early to avoid flash of wrong theme
  const { initializeTheme } = useTheme();
  onMounted(initializeTheme);

  const bootstrapStore = useBootstrapStore();
  const { global_banner, global_banner_scope } = storeToRefs(bootstrapStore);

  // Component key cannot be null or undefined
  const globalBroadcastKey = computed(() => global_banner.value ? 'globalBroadcast' : 'noBroadcast');

  const identityStore = useProductIdentity();

  // If there's a global banner set (in redis), this will be true.
  const hasGlobalBanner = computed(() => !!global_banner.value);

  /**
   * Whether the banner's audience scope permits this page.
   *
   * The banner carries a scope (set on /colonel/banner). Custom-domain pages are
   * suppressed UNLESS the operator chose 'all' (truly global), because branded
   * recipient surfaces shouldn't carry OTS-operator announcements by default.
   *
   *   all           → every audience, including custom domains + recipient pages
   *   no_recipient  → every audience except recipient; not on custom domains
   *   workspace     → workspace pages only; not on custom domains
   */
  const audienceAllows = computed(() => {
    const scope = global_banner_scope.value ?? 'no_recipient';
    const audience = props.bannerAudience;

    if (identityStore.domainStrategy === 'custom') {
      return scope === 'all';
    }

    switch (scope) {
      case 'all':
        return true;
      case 'workspace':
        return audience === 'workspace';
      case 'no_recipient':
      default:
        return audience !== 'recipient';
    }
  });

  // Show the broadcast only when the feature is on for this layout, a banner
  // exists, AND the banner's audience scope permits this page.
  const shouldBroadcast = computed(
    () => props.displayGlobalBroadcast && hasGlobalBanner.value && audienceAllows.value
  );

  // Compute primary color styles based on brand color or prop
  const primaryColorClass = computed(() => {
    const currentColor = identityStore.primaryColor;
    return !isColorValue(currentColor) ? currentColor : '';
  });

  const primaryColorStyle = computed(() => {
    const currentColor = identityStore.primaryColor;
    return isColorValue(currentColor) ? { backgroundColor: currentColor } : {};
  });
</script>

<template>
  <div data-testid="base-layout" class="flex min-h-screen flex-col">
    <!-- All along the watch tower -->
    <div
      class="fixed left-0 top-0 z-50 h-1 w-full"
      :class="primaryColorClass"
      :style="primaryColorStyle"></div>

    <!-- Good morning Vietnam -->
    <GlobalBroadcast
      v-if="shouldBroadcast"
      :show="true"
      :content="global_banner ?? null"
      :key="globalBroadcastKey"
      :expiration-days="7" />

    <!-- Rest of the owl -->
    <slot name="header"></slot>
    <slot name="main"></slot>
    <slot name="footer"></slot>
    <slot name="status">
      <div id="status-messages"></div>
    </slot>
  </div>
</template>
