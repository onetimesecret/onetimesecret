<!-- src/components/layout/FooterLinks.vue -->

<script setup lang="ts">
  import { WindowService } from '@/services/window.service';
  import type { FooterLinksConfig } from '@/types/declarations/window';
  import { computed } from 'vue';

  const windowProps = WindowService.getMultiple(['ui']);

  const footerConfig = computed((): FooterLinksConfig | null => {
    return windowProps.ui?.footer_links || null;
  });

  const isEnabled = computed((): boolean => {
    return footerConfig.value?.enabled === true;
  });

  const linkGroups = computed(() => {
    return footerConfig.value?.groups || [];
  });
</script>

<template>
  <div
    v-if="isEnabled"
    class="w-full border-t border-gray-200 pt-8 dark:border-gray-700">
    <!-- prettier-ignore-attribute class -->
    <div
      class="
      grid grid-cols-1 gap-6
      sm:grid-cols-2
      md:grid-cols-3
      lg:grid-cols-4">
      <div
        v-for="group in linkGroups"
        :key="group.name"
        class="space-y-3">
        <!-- Group title -->
        <h3
          v-if="group.i18n_key"
          class="text-sm font-semibold text-gray-900 dark:text-gray-100">
          {{ $t(group.i18n_key) }}
        </h3>

        <!-- Links list -->
        <ul class="space-y-2">
          <li
            v-for="link in group.links"
            :key="link.url">
            <!-- prettier-ignore-attribute class -->
            <a
              :href="link.url"
              :target="link.external ? '_blank' : '_self'"
              :rel="link.external ? 'noopener noreferrer' : ''"
              class="
                 inline-flex items-center gap-2
                 text-sm text-gray-600
                 transition-colors duration-200
                 hover:text-gray-900
                 dark:text-gray-400
                 dark:hover:text-gray-100">
              <!-- Optional icon -->
              <i
                v-if="link.icon"
                :class="`icon-${link.icon}`"
                class="text-xs"
                :aria-hidden="true"></i>

              <!-- Link text -->
              <span>{{ link.i18n_key ? $t(link.i18n_key) : link.text }}</span>

              <!-- External link indicator -->
              <i
                v-if="link.external"
                class="icon-external-link text-xs opacity-60"
                :aria-label="$t('web.COMMON.external_link')"
                :aria-hidden="true"></i>
            </a>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
