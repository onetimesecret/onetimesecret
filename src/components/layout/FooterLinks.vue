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
      grid grid-cols-1 gap-8
      sm:grid-cols-2
      md:grid-cols-3
      lg:grid-cols-4">
      <div
        v-for="(group, groupIndex) in linkGroups"
        :key="group.name || `group-${groupIndex}`"
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
            v-for="(link, linkIndex) in group.links || []"
            :key="link.url || `link-${linkIndex}`">
            <!-- prettier-ignore-attribute class -->
            <a
              v-if="link.url && link.url.trim()"
              :href="link.url"
              :target="link.external ? '_blank' : '_self'"
              :rel="link.external ? 'noopener noreferrer' : ''"
              class="
                 block
                 text-sm text-gray-600
                 transition-colors duration-200
                 hover:text-gray-900
                 dark:text-gray-400
                 dark:hover:text-gray-100">
              <!-- Content wrapper for consistent spacing -->
              <span class="inline-flex items-center gap-2">
                <!-- Optional icon -->
                <i
                  v-if="link.icon"
                  :class="`icon-${link.icon}`"
                  class="text-xs flex-shrink-0"
                  :aria-hidden="true"></i>

                <!-- Link text -->
                <span class="flex-1">{{ link.i18n_key ? $t(link.i18n_key) : link.text }}</span>

                <!-- External link indicator -->
                <i
                  v-if="link.external"
                  class="icon-external-link text-xs opacity-60 flex-shrink-0"
                  :aria-label="$t('web.COMMON.external_link')"
                  :aria-hidden="true"></i>
              </span>
            </a>
            <!-- Fallback for missing/empty URLs -->
            <span
              v-else
              class="
                 block
                 text-sm text-gray-400
                 dark:text-gray-500">
              {{ link.i18n_key ? $t(link.i18n_key) : link.text }}
            </span>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
