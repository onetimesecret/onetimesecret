<!-- src/shared/components/layout/FooterLinks.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { FooterLinksConfig } from '@/types/declarations/bootstrap';
  import OIcon from '@/shared/components/icons/OIcon.vue';
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
    <div
      class="grid max-w-6xl grid-cols-1 justify-items-start gap-x-12 gap-y-8 px-4 sm:grid-cols-[repeat(auto-fit,minmax(140px,1fr))] sm:items-start sm:justify-items-start md:grid-cols-[repeat(auto-fit,minmax(160px,1fr))] lg:grid-cols-[repeat(auto-fit,minmax(180px,1fr))]">
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
              <span class="inline-flex items-center gap-1.5">
                <span>{{ link.i18n_key ? t(link.i18n_key) : link.text }}</span>
                <OIcon
                  v-if="link.icon"
                  collection="heroicons"
                  :name="link.icon"
                  class="size-3.5 shrink-0 opacity-60" />
                <OIcon
                  v-if="link.external"
                  collection="heroicons"
                  name="arrow-top-right-on-square"
                  class="size-3 shrink-0 opacity-50" />
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
