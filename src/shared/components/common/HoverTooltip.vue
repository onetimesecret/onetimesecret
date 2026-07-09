<!-- src/shared/components/common/HoverTooltip.vue -->

<script setup lang="ts">
  import { useId } from 'vue';

  const props = withDefaults(
    defineProps<{
      /** Optional explicit ID for aria-describedby linkage. Auto-generated if omitted. */
      tooltipId?: string;
      /** Classes for the tooltip bubble's width/alignment. Defaults suit short labels. */
      contentClass?: string;
    }>(),
    {
      contentClass: 'min-w-[100px] text-center',
    }
  );

  const autoId = useId();
  const id = props.tooltipId ?? `tooltip-${autoId}`;

  defineExpose({ id });
</script>

<template>
  <div
    :id="id"
    role="tooltip"
    class="pointer-events-none invisible absolute bottom-full left-1/2 z-50 mb-2
           -translate-x-1/2 opacity-0 transition-opacity duration-200
           group-focus-within:visible group-focus-within:opacity-100
           group-hover:visible group-hover:opacity-100">
    <div class="flex flex-col items-center">
      <div
        :class="[
          'rounded-md bg-gray-900 px-2 py-1 text-xs text-white shadow-lg dark:bg-gray-700 dark:text-gray-100',
          contentClass,
        ]">
        <slot></slot>
      </div>
      <div
        class="mt-0.5 -mb-1 size-2 rotate-45
                  bg-gray-900 dark:bg-gray-700"></div>
    </div>
  </div>
</template>
