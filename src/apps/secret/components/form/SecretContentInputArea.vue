<!-- src/components/secrets/form/SecretContentInputArea.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useCharCounter } from '@/shared/composables/useCharCounter';
  import { useTextarea } from '@/shared/composables/useTextarea';
  import { computed, watch } from 'vue';

const { t } = useI18n();

  const props = withDefaults(
    defineProps<{
      maxLength?: number;
      initialContent?: string;
      cornerClass?: string;
      disabled?: boolean;
      minHeight?: number;
      maxHeight?: number;
    }>(),
    {
      maxLength: 10000,
      disabled: false,
      initialContent: '',
      cornerClass: '',
      minHeight: 200,
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
    <!-- <div
      id="textarea-focus-announcement"
      aria-live="polite"
      class="sr-only">
      {{ t('focus-is-now-in-the-main-text-area') }}
    </div> -->
    <!-- prettier-ignore-attribute class -->
    <textarea
      ref="textareaRef"
      v-model="content"
      :disabled="disabled"
      @input="checkContentLength"
      :maxlength="maxLength"
      :class="[cornerClass]"
      :style="{ minHeight: minHeight + 'px', maxHeight: maxHeight + 'px' }"
      class="
        block w-full resize-none
        rounded-lg border border-gray-200/60 p-5
        font-mono text-base leading-relaxed
        text-gray-900 transition-all
        duration-300 placeholder:text-gray-400
        bg-white/80 backdrop-blur-sm
        hover:border-gray-300/80 hover:bg-white/90
        focus:border-blue-500/80 focus:bg-white
        focus:ring-4 focus:ring-blue-500/20
        disabled:bg-gray-50/80 disabled:text-gray-500
        dark:border-gray-700/60 dark:bg-slate-800/80
        dark:text-white dark:placeholder:text-gray-500
        dark:hover:border-gray-600/80 dark:hover:bg-slate-800/90
        dark:focus:border-blue-400/80 dark:focus:bg-slate-800
        dark:focus:ring-blue-400/20
        dark:disabled:bg-slate-900/50
      "
      :placeholder="t('web.COMMON.secret_placeholder')"
      :aria-label="t('enter-the-secret-content-here')">
    </textarea>

    <!--
      Generally speaking, v-if has higher toggle costs while v-show has higher
      initial render costs. So prefer v-show if you need to toggle something
      very often, and prefer v-if if the condition is unlikely to change at
      runtime. -- https://vuejs.org/guide/essentials/conditional.html#v-if-vs-v-show
    -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-if="showCounter"
      class="pointer-events-none absolute bottom-4 right-4 flex select-none items-center gap-2
        rounded-full bg-white/95 px-3.5 py-1.5 text-sm
        shadow-[0_4px_12px_rgba(0,0,0,0.1),0_1px_3px_rgba(0,0,0,0.08)]
        backdrop-blur-md transition-all duration-300 border border-gray-200/40
        dark:bg-gray-800/95 dark:border-gray-700/40
        dark:shadow-[0_4px_12px_rgba(0,0,0,0.3),0_1px_3px_rgba(0,0,0,0.2)]">
      <span
        :class="[statusColor, 'size-2.5 rounded-full shadow-sm']"
        aria-hidden="true"></span>
      <span class="font-semibold text-gray-700 dark:text-gray-300 tabular-nums">
        {{ formattedCharCount }} / {{ formattedMaxLength }}
      </span>
    </div>
  </div>
</template>
