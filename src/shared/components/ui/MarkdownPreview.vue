<!-- src/shared/components/ui/MarkdownPreview.vue -->

<script setup lang="ts">
  /**
   * Live Markdown preview: the hybrid half of the secret editor.
   *
   * Renders what the recipient will see, with the same renderer and
   * sanitizer as the reveal page, while the form's textarea stays the single
   * place the text is edited. Shared by the homepage and workspace forms.
   */
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import MarkdownRenderer from '@/shared/components/ui/MarkdownRenderer.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const props = withDefaults(
    defineProps<{
      /** Markdown source, as typed in the form's textarea */
      source: string;
      /** Brand corner class for the preview box */
      cornerClass?: string;
      /** Height cap and padding for the preview box, sized to the form */
      boxClass?: string;
    }>(),
    {
      cornerClass: '',
      boxClass: 'max-h-[400px] p-5',
    }
  );

  const { t } = useI18n();

  const hasContent = computed(() => props.source.trim().length > 0);
</script>

<template>
  <div
    class="mt-3"
    data-testid="secret-markdown-preview">
    <!-- prettier-ignore-attribute class -->
    <div
      class="mb-1 flex items-center gap-1.5 text-xs font-medium tracking-wide
        text-gray-500 uppercase dark:text-gray-400">
      <OIcon
        collection="heroicons"
        name="eye"
        class="size-3.5"
        aria-hidden="true" />
      {{ t('web.secrets.markdown_preview') }}
    </div>
    <!-- prettier-ignore-attribute class -->
    <div
      :class="[cornerClass, boxClass]"
      class="overflow-auto rounded-lg border border-dashed border-gray-300/80 bg-white/60
        dark:border-gray-600/80 dark:bg-slate-800/50">
      <MarkdownRenderer
        v-if="hasContent"
        :source="source"
        :debounce="150" />
      <p
        v-else
        class="text-sm text-gray-400 italic dark:text-gray-500">
        {{ t('web.secrets.markdown_preview_empty') }}
      </p>
    </div>
  </div>
</template>
