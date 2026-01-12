<!-- src/shared/components/layout/FooterLinks.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { FooterLinksConfig } from '@/types/declarations/window';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';

  const { t } = useI18n();

  const bootstrapStore = useBootstrapStore();
  const { ui } = storeToRefs(bootstrapStore);

  const footerConfig = computed((): FooterLinksConfig | null => ui.value?.footer_links || null);

  const isEnabled = computed((): boolean => footerConfig.value?.enabled === true);

  const linkGroups = computed(() => footerConfig.value?.groups || []);
</script>

<template>
  <div
    v-if="isEnabled"
    class="flex w-full justify-center border-t border-gray-200 pt-8 dark:border-gray-700">
    <!-- prettier-ignore-attribute class -->
    <div
      class="
      grid max-w-6xl grid-cols-1
      justify-items-start gap-x-12
      gap-y-8 px-4
      [@media(min-width:1024px)]:grid-cols-[repeat(auto-fit,minmax(180px,1fr))]
      [@media(min-width:640px)]:grid-cols-[repeat(auto-fit,minmax(140px,1fr))]
      [@media(min-width:640px)]:items-start [@media(min-width:640px)]:justify-items-center [@media(min-width:768px)]:grid-cols-[repeat(auto-fit,minmax(160px,1fr))]">
      <div
        v-for="(group, groupIndex) in linkGroups"
        :key="group.name || `group-${groupIndex}`"
        class="space-y-3">
        <!-- Group title - modify font size here (text-sm) -->
        <h3
          v-if="group.i18n_key"
          class="text-sm font-semibold text-gray-900 dark:text-gray-100">
          {{ t(group.i18n_key) }}
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
                <!-- Optional icon - modify icon size here (text-xs) -->
                <i
                  v-if="link.icon"
                  :class="`icon-${link.icon}`"
                  class="shrink-0 text-xs"
                  :aria-hidden="true"></i>

                <!-- Link text - modify link font size here (text-sm) -->
                <span class="flex-1">{{ link.i18n_key ? t(link.i18n_key) : link.text }}</span>

                <!-- External link indicator -->
                <i
                  v-if="link.external"
                  class="icon-external-link shrink-0 text-xs opacity-60"
                  :aria-label="t('web.COMMON.external_link')"
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
              {{ link.i18n_key ? t(link.i18n_key) : link.text }}
            </span>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
