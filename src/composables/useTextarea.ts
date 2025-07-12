// src/composables/useTextarea.ts

import { onMounted, ref, watch } from 'vue';

interface TextareaOptions {
  maxLength: number;
  initialContent?: string;
  maxHeight?: number;
  onContentChange?: (content: string) => void;
}

/* eslint-disable max-lines-per-function */
export function useTextarea(options: TextareaOptions) {
  const content = ref(options.initialContent || '');
  const charCount = ref(0);
  const textareaRef = ref<HTMLTextAreaElement | null>(null);
  const maxHeight = options.maxHeight || 400;

  const adjustHeight = () => {
    if (textareaRef.value) {
      textareaRef.value.style.height = 'auto';
      const newHeight = Math.min(textareaRef.value.scrollHeight, maxHeight);
      textareaRef.value.style.height = `${newHeight}px`;
    }
  };
  const clearTextarea = () => {
    content.value = '';
    charCount.value = 0;
    if (textareaRef.value) {
      textareaRef.value.style.height = 'auto';
    }
    adjustHeight();
    options.onContentChange?.('');
  };

  const checkContentLength = (event: Event) => {
    const target = event.target as HTMLTextAreaElement;
    const newValue = target.value;

    if (newValue.length <= options.maxLength) {
      content.value = newValue;
      charCount.value = newValue.length;
    } else {
      // Truncate content if it exceeds maxLength
      content.value = newValue.slice(0, options.maxLength);
      charCount.value = options.maxLength;
      // Update textarea value to reflect truncated content
      target.value = content.value;
    }

    adjustHeight();
    options.onContentChange?.(content.value);
  };

  const handleInput = (event: Event) => {
    const target = event.target as HTMLTextAreaElement;
    if (target.value.length <= options.maxLength) {
      content.value = target.value;
      charCount.value = target.value.length;
    } else {
      content.value = target.value.slice(0, options.maxLength);
      charCount.value = options.maxLength;
      target.value = content.value;
    }
    adjustHeight();
  };

  // Watch for external content changes
  watch(content, (newContent) => {
    charCount.value = newContent.length;
    adjustHeight();
    options.onContentChange?.(newContent);
  });

  onMounted(() => {
    charCount.value = content.value.length;
    adjustHeight();
  });

  return {
    content,
    clearTextarea,
    charCount,
    textareaRef,
    checkContentLength,
    handleInput,
  };
}
