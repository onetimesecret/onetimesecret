<!-- src/shared/components/closet/SettingsSkeleton.vue -->

<script setup lang="ts">
  /**
   * SettingsSkeleton
   *
   * General, prop-driven loading placeholder for the settings-page archetype
   * (the highest-leverage shape in the #3269 inventory: 9 TARGET sites across
   * account settings, org settings, billing overview, and domain-detail pages).
   *
   * Structure: an optional heading block followed by N field groups, each a
   * short label line over a full-width input bar. The form-fields archetype
   * (config forms whose fields await an API) is the same shape with no heading,
   * so pass `:heading="false"` rather than reaching for a separate component.
   *
   * This is generic chrome. For a skeleton that mirrors one specific page's
   * header + tab bar, build a co-located page-specific skeleton instead
   * (see OrgSettingsSkeleton.vue).
   *
   * a11y: the wrapper announces itself as a busy status region with an sr-only
   * loading label; the wrapper owns the single pulse, so every child Skeleton
   * passes `:pulse="false"`.
   */
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';

  interface Props {
    /** Number of label+input field groups to render. */
    groups?: number;
    /** Render a leading section-heading block. */
    heading?: boolean;
  }

  withDefaults(defineProps<Props>(), {
    groups: 3,
    heading: true,
  });

  const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    class="animate-pulse space-y-6 motion-reduce:animate-none">
    <span class="sr-only">{{ t('web.COMMON.loading') }}</span>

    <!-- Section heading -->
    <Skeleton
      v-if="heading"
      width="w-1/3"
      height="h-6"
      :pulse="false" />

    <!-- Field groups: label line over a full-width input bar -->
    <div
      v-for="n in groups"
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
</template>
