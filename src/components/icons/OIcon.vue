<!--
  Usage:

    <OIcon
      class="size-5"
      collection="heroicons-solid"
      name="ellipsis-vertical"
      aria-label="More options"  // Add aria-label for meaningful icons.
    />
    <OIcon
      class="size-5"
      collection="heroicons-solid"
      name="close"
      :aria-hidden="false"       // Override aria-hidden if the icon is interactive
      @click="closeModal"        // Example: Make the close icon interactive
    />

  NOTE: The content of aria-label is key: it should be meaningful in the context where the icon is used.
-->

<script setup lang="ts">
  import { computed } from 'vue';

  export interface Props {
    collection: string; // heroicons-solid
    name: string; // ellipses-vertical
    size?: string; // size-5
    ariaLabel?: string; // Add aria-label prop
  }

  const props = withDefaults(defineProps<Props>(), {
    ariaLabel: undefined,
    size: "5",
  });
  const size = computed(() => `size-${props.size ?? 5}`);
  const iconId = computed(() => `${props.collection}-${props.name}`);
  const ariaLabel = computed(() => props.ariaLabel ?? `${iconId.value} icon`);

  // Professional iconist tip:
  // It's very helpful to console log the props here to see what icons
  // are coming through with the wrong combo of collection and/or name.
</script>

<template>
  <svg
    :class="size"
    :aria-hidden="true"
    :aria-label="ariaLabel"
    role="img">
    <title v-if="ariaLabel">{{ ariaLabel }}</title>
    <use :href="`#${iconId}`" />
  </svg>
</template>
