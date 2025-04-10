<!-- src/components/secrets/form/SecretContentInputArea.vue -->

<script setup lang="ts">
  import { useCharCounter } from '@/composables/useCharCounter';
  import { useTextarea } from '@/composables/useTextarea';
  import { computed, watch } from 'vue';

  const props = withDefaults(
    defineProps<{
      maxLength?: number;
      initialContent?: string;
      cornerClass?: string;
      disabled?: boolean;
      minHeight?: string;
      maxHeight?: number;
    }>(),
    {
      maxLength: 10000,
      disabled: false,
      minHeight: '200px',
      maxHeight: 400,
    }
  );

  const emit = defineEmits(['update:content']);

  const { content, charCount, textareaRef, checkContentLength, clearTextarea } = useTextarea({
    maxLength: props.maxLength || 10000,
    initialContent: props.initialContent,
    maxHeight: props.maxHeight,
    onContentChange: (newContent) => emit('update:content', newContent),
  });

  const { isHovering, formatNumber } = useCharCounter();

  // Computed properties
  const showCounter = computed(() => isHovering.value || charCount.value > props.maxLength! / 2);

  const formattedCharCount = computed(() => formatNumber(charCount.value));

  const formattedMaxLength = computed(() => formatNumber(props.maxLength!));

  const statusColor = computed(() => {
    const percentage = charCount.value / props.maxLength!;
    if (percentage < 0.8) return 'bg-emerald-400 dark:bg-emerald-500';
    if (percentage < 0.95) return 'bg-amber-400 dark:bg-amber-500';
    return 'bg-red-400 dark:bg-red-500';
  });

  // Watch for changes to emit updates
  watch(content, (newContent) => {
    emit('update:content', newContent);
  });

  defineExpose({ clearTextarea });
</script>

<template>
  <div class="relative">
    <textarea
      ref="textareaRef"
      v-model="content"
      :disabled="disabled"
      @input="checkContentLength"
      :maxlength="maxLength"
      :class="[cornerClass]"
      :style="{ minHeight: minHeight, maxHeight: maxHeight + 'px' }"
      class="
        block w-full resize-none
        rounded-lg border border-gray-200 p-4
        font-mono text-base leading-relaxed
        text-gray-900 placeholder:text-gray-400
        focus:border-blue-500 focus:ring-2 focus:ring-blue-500
        disabled:bg-gray-50 disabled:text-gray-500
        dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500
        dark:focus:border-blue-400 dark:focus:ring-blue-400
        transition-all duration-200
      "
      :placeholder="$t('web.COMMON.secret_placeholder')"
      :aria-label="$t('enter-the-secret-content-here')">
    </textarea>

    <!--
      Generally speaking, v-if has higher toggle costs while v-show has higher
      initial render costs. So prefer v-show if you need to toggle something
      very often, and prefer v-if if the condition is unlikely to change at
      runtime. -- https://vuejs.org/guide/essentials/conditional.html#v-if-vs-v-show
    -->
    <div
      v-if="showCounter"
      class="pointer-events-none select-none absolute bottom-3 right-3 rounded-full px-3 py-1 text-sm shadow-sm transition-colors duration-200 flex items-center gap-1.5 bg-white/90 dark:bg-gray-800/90 backdrop-blur-sm">
      <span :class="[statusColor, 'w-2.5 h-2.5 rounded-full']" aria-hidden="true"></span>
      <span class="text-gray-600 dark:text-gray-400 font-medium">{{ formattedCharCount }} / {{ formattedMaxLength }}</span>
    </div>
  </div>
</template>
