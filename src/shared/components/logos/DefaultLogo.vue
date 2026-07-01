<!-- src/shared/components/logos/DefaultLogo.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import KeyholeIcon from '@/shared/components/icons/KeyholeIcon.vue';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { type LogoConfig } from '@/types/ui/layouts';
  import { computed } from 'vue';

  /**
   * Props for controlling logo appearance
   */
  const props = withDefaults(
    defineProps<LogoConfig & { isColonelArea?: boolean }>(),
    {
      size: 64,
      href: '/',
      isColonelArea: false,
    }
  );

  const { t } = useI18n();
  const identity = useProductIdentity();

  /**
   * Brand-aware aria-label. Falls back to the resolver's neutral-safe
   * `productName` (a generic "My App") when bootstrap config has not provided a
   * brand name. Never defaults to OTS branding — keeps private-label
   * deployments neutral (#3048 / #3049). Resolving the fallback through
   * `identityStore.productName` keeps this in lockstep with every other
   * name-rendering surface instead of re-deriving the chain here.
   */
  const ariaLabel = computed(() => props.ariaLabel || identity.productName);

  const svgSize = computed(() =>
    typeof props.size === 'number' && props.size > 0 ? props.size : 64
  );

  const textSize = computed(() => {
    if (props.size <= 32) return 'text-xs';
    if (props.size <= 40) return 'text-sm';
    if (props.size <= 48) return 'text-base';
    if (props.size <= 64) return 'text-lg';
    return 'text-xl';
  });
</script>

<template>
  <!-- The wrapping <div> is a non-interactive layout container, so it carries no
       aria-label: the accessible name comes from the KeyholeIcon inside the <a>.
       Labelling both would announce the name twice (#3553 review). -->
  <div class="flex items-center gap-3">
    <a
      :href="props.href"
      class="flex items-center gap-3">
      <!-- Logo Mark: neutral keyhole (matches the favicon generator's
           brand-neutral default; the maruhi 秘 mark is OTS-company-only). -->
      <KeyholeIcon
        :size="svgSize"
        :aria-label="ariaLabel"
        :title="t('web.branding.keyhole_logo_icon', 'Keyhole secure sharing icon')"
        class="shrink-0 text-brand-500 dark:text-white" />
      <!-- Text Mark -->
      <!-- Company Name -->
      <div
        v-if="props.showSiteName && props.siteName"
        class="relative flex flex-col">
        <div :class="[textSize, 'font-brand font-bold leading-tight']">
          {{ props.siteName }}
        </div>
        <!-- Colonel Overlay -->
        <div
          v-if="props.isColonelArea"
          class="pointer-events-none absolute inset-0 flex items-center justify-center">
          <span
            class="-rotate-6 transform-gpu rounded-lg bg-brand-500 px-2 py-1 text-sm font-bold tracking-widest text-white shadow-lg dark:bg-brand-600/90"
            style="transform-origin: center;">
            {{ t('web.layout.colonels_only_badge') }}
          </span>
        </div>
        <!-- Tagline -->
        <div
          class="text-xs text-gray-500 transition-colors dark:text-gray-400"
          aria-hidden="true">
          {{ props.tagLine || t('web.COMMON.tagline') }}
        </div>
      </div>
    </a>
  </div>
</template>
