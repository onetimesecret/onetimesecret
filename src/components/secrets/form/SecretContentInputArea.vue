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
  <div class="group/textarea relative">
    <!-- <div
      id="textarea-focus-announcement"
      aria-live="polite"
      class="sr-only">
      {{ $t('focus-is-now-in-the-main-text-area') }}
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
        rounded-xl border-2 border-gray-300/60 bg-white/50 p-5
        font-mono text-base leading-relaxed
        text-gray-900 backdrop-blur-sm transition-all
        duration-200 placeholder:text-gray-400
        hover:border-gray-400/60 hover:bg-white/80
        focus:border-blue-500 focus:bg-white
        focus:outline-none focus:ring-4 focus:ring-blue-500/20
        disabled:bg-gray-50 disabled:text-gray-500
        dark:border-gray-600/60 dark:bg-slate-800/50
        dark:text-white dark:placeholder:text-gray-500
        dark:hover:border-gray-500/60 dark:hover:bg-slate-800/80
        dark:focus:border-blue-400 dark:focus:bg-slate-800 dark:focus:ring-blue-400/20
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
    <!-- prettier-ignore-attribute class -->
    <div
      v-if="showCounter"
      class="pointer-events-none absolute bottom-4 right-4 flex select-none items-center gap-2
        rounded-full bg-white/95 px-3.5 py-2 text-sm shadow-lg
        ring-1 ring-gray-900/5
        backdrop-blur-md transition-all duration-300
        dark:bg-gray-800/95 dark:ring-white/10">
      <span
        :class="[statusColor, 'size-2 rounded-full shadow-sm']"
        aria-hidden="true"></span>
      <span class="font-semibold tabular-nums text-gray-700 dark:text-gray-300">
        {{ formattedCharCount }} <span class="text-gray-400 dark:text-gray-500">/</span> {{ formattedMaxLength }}
      </span>
    </div>
  </div>
</template>
