<!-- src/shared/components/ui/MarkdownRenderer.vue -->

<script setup lang="ts">
  /**
   * Renders Markdown as sanitized HTML.
   *
   * Used for secrets with display_type 'markdown': the live preview on the
   * create forms and the recipient's reveal page. The parser, highlighter and
   * sanitizer (src/shared/utils/markdown.ts) load on first use, so plain-text
   * secrets never pay for highlight.js. If rendering fails for any reason the
   * source is shown as plain text instead: a recipient must never lose the
   * value to a rendering bug.
   */
  import { loggingService } from '@/services/logging.service';
  import { watchDebounced } from '@vueuse/core';
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const props = withDefaults(
    defineProps<{
      /** Markdown source text */
      source: string;
      /** Milliseconds to wait after the source changes before re-rendering (0 renders at once) */
      debounce?: number;
    }>(),
    { debounce: 0 }
  );

  const { t } = useI18n();

  type RenderFn = (source: string) => string;

  const html = ref('');
  const isLoading = ref(true);
  const failed = ref(false);

  let renderFn: RenderFn | null = null;
  let loading: Promise<RenderFn> | null = null;

  const loadRenderer = (): Promise<RenderFn> => {
    loading ??= import('@/shared/utils/markdown').then((mod) => {
      renderFn = mod.renderMarkdown;
      return renderFn;
    });
    return loading;
  };

  // Monotonic ticket: a slow first load must not overwrite a newer render.
  let latest = 0;

  const render = async (source: string) => {
    const ticket = ++latest;
    try {
      const fn = renderFn ?? (await loadRenderer());
      if (ticket !== latest) return;
      html.value = fn(source);
      failed.value = false;
    } catch (error) {
      if (ticket !== latest) return;
      failed.value = true;
      loggingService.error(error instanceof Error ? error : new Error(String(error)));
    } finally {
      if (ticket === latest) isLoading.value = false;
    }
  };

  watchDebounced(
    () => props.source,
    (source) => {
      void render(source);
    },
    { debounce: props.debounce, immediate: true }
  );
</script>

<template>
  <div>
    <p
      v-if="isLoading"
      class="text-sm text-gray-500 dark:text-gray-400"
      role="status"
      aria-live="polite">
      {{ t('web.secrets.markdown_rendering') }}
    </p>
    <!-- prettier-ignore-attribute class -->
    <pre
      v-else-if="failed"
      class="font-mono text-sm wrap-break-word whitespace-pre-wrap
        text-gray-900 dark:text-gray-100"
      data-testid="markdown-fallback"
      v-text="source"></pre>
    <!--
      `html` comes from renderMarkdown(), which sanitizes with DOMPurify
      (src/shared/utils/markdown.ts). Nothing else may be bound here.
    -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-else
      class="markdown-body prose prose-sm max-w-none wrap-break-word
        sm:prose-base dark:prose-invert"
      data-testid="markdown-rendered"
      v-html="html"></div>
  </div>
</template>

<style>
  /*
   * highlight.js token palette for fenced code blocks (GitHub Dark). Not
   * scoped: the markup is injected with v-html, so scoped attributes would
   * never reach it. Tailwind's typography plugin already paints <pre> dark in
   * both color schemes (--tw-prose-pre-bg), so one dark-background palette
   * serves light and dark mode.
   */
  .markdown-body .hljs-comment,
  .markdown-body .hljs-quote {
    color: #8b949e;
    font-style: italic;
  }

  .markdown-body .hljs-keyword,
  .markdown-body .hljs-selector-tag,
  .markdown-body .hljs-doctag,
  .markdown-body .hljs-template-tag,
  .markdown-body .hljs-meta .hljs-keyword {
    color: #ff7b72;
  }

  .markdown-body .hljs-title,
  .markdown-body .hljs-title.class_,
  .markdown-body .hljs-title.function_,
  .markdown-body .hljs-section {
    color: #d2a8ff;
    font-weight: 600;
  }

  .markdown-body .hljs-attr,
  .markdown-body .hljs-attribute,
  .markdown-body .hljs-literal,
  .markdown-body .hljs-number,
  .markdown-body .hljs-operator,
  .markdown-body .hljs-variable,
  .markdown-body .hljs-template-variable,
  .markdown-body .hljs-selector-attr,
  .markdown-body .hljs-selector-class,
  .markdown-body .hljs-selector-id,
  .markdown-body .hljs-meta {
    color: #79c0ff;
  }

  .markdown-body .hljs-string,
  .markdown-body .hljs-regexp,
  .markdown-body .hljs-meta .hljs-string {
    color: #a5d6ff;
  }

  .markdown-body .hljs-built_in,
  .markdown-body .hljs-symbol,
  .markdown-body .hljs-type {
    color: #ffa657;
  }

  .markdown-body .hljs-name,
  .markdown-body .hljs-tag,
  .markdown-body .hljs-bullet,
  .markdown-body .hljs-subst {
    color: #7ee787;
  }

  .markdown-body .hljs-addition {
    color: #aff5b4;
    background-color: #033a16;
  }

  .markdown-body .hljs-deletion {
    color: #ffdcd7;
    background-color: #67060c;
  }

  .markdown-body .hljs-emphasis {
    font-style: italic;
  }

  .markdown-body .hljs-strong {
    font-weight: 700;
  }

  /* Wide tables scroll inside the card instead of breaking the layout. */
  .markdown-body table {
    display: block;
    overflow-x: auto;
  }
</style>
