<!-- src/apps/secret/components/SecretMarkdownContent.vue -->

<script setup lang="ts">
  /**
   * Revealed secret content for display_type 'markdown'.
   *
   * Shows the rendered Markdown by default and lets the recipient flip to
   * the source: the raw text is what the copy button copies, and a reader
   * who wants exactly what the sender typed should be able to see it.
   * Shared by the canonical and branded SecretDisplayCase components.
   */
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import MarkdownRenderer from '@/shared/components/ui/MarkdownRenderer.vue';
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  type ViewMode = 'rendered' | 'source';

  withDefaults(
    defineProps<{
      /** The decrypted secret value (Markdown source) */
      content: string;
      /** id for the source textarea, so a caller's label can point at it */
      contentId: string;
      /** Rows for the source textarea (details.display_lines) */
      rows?: number;
      /** Brand corner class for the content box */
      cornerClass?: string;
    }>(),
    {
      rows: 4,
      cornerClass: 'rounded-md',
    }
  );

  const { t } = useI18n();

  const mode = ref<ViewMode>('rendered');

  const modeButtonClass = (active: boolean) => [
    'px-2.5 py-1 text-xs font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:z-10',
    active
      ? 'bg-brand-50 text-brand-700 dark:bg-brand-900/40 dark:text-brand-300'
      : 'bg-white text-gray-600 hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700',
  ];
</script>

<template>
  <div>
    <div class="mb-2 flex items-center justify-between gap-3">
      <!-- prettier-ignore-attribute class -->
      <span
        class="inline-flex items-center gap-1.5 text-xs font-medium tracking-wide
          text-gray-500 uppercase dark:text-gray-400">
        <OIcon
          collection="mdi"
          name="language-markdown"
          class="size-4"
          aria-hidden="true" />
        {{ t('web.secrets.markdown_mode') }}
      </span>
      <!-- prettier-ignore-attribute class -->
      <div
        role="group"
        :aria-label="t('web.secrets.markdown_display_mode')"
        class="inline-flex overflow-hidden rounded-md ring-1 ring-gray-300 ring-inset
          dark:ring-gray-600">
        <button
          type="button"
          :class="modeButtonClass(mode === 'rendered')"
          :aria-pressed="mode === 'rendered'"
          data-testid="secret-markdown-view-rendered"
          @click="mode = 'rendered'">
          {{ t('web.secrets.markdown_rendered') }}
        </button>
        <button
          type="button"
          :class="modeButtonClass(mode === 'source')"
          :aria-pressed="mode === 'source'"
          data-testid="secret-markdown-view-source"
          @click="mode = 'source'">
          {{ t('web.secrets.markdown_source') }}
        </button>
      </div>
    </div>

    <!-- prettier-ignore-attribute class -->
    <div
      v-if="mode === 'rendered'"
      :class="[cornerClass]"
      class="max-h-[70vh] overflow-auto border border-gray-300 bg-white px-4 py-3
        dark:border-gray-600 dark:bg-gray-900"
      role="region"
      tabindex="0"
      :aria-label="t('web.secrets.secret_content')"
      data-testid="secret-content-markdown">
      <MarkdownRenderer :source="content" />
    </div>
    <template v-else>
      <label
        :for="contentId"
        class="sr-only">
        {{ t('web.secrets.secret_content') }}
      </label>
      <!-- prettier-ignore-attribute class -->
      <textarea
        :id="contentId"
        :class="[cornerClass]"
        class="w-full resize-none border border-gray-300 bg-gray-100 px-3 py-2 font-mono text-base
          leading-[1.2] focus:ring-2 focus:ring-brand-500 focus:outline-none
          dark:border-gray-600 dark:bg-gray-800 dark:text-white"
        readonly
        :rows="rows"
        :value="content"
        :aria-label="t('web.secrets.secret_content')"
        data-testid="secret-content"></textarea>
    </template>
  </div>
</template>
