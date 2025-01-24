<!--
  Usage:

    <OIcon
      class="size-5"
      collection="heroicons-solid"
      name="ellipsis-vertical" />
-->

<script setup lang="ts">
  export interface Props {
    collection: string; // heroicons-solid
    name: string; // ellipses-vertical
    size?: string; // size-5
  }
  const props = defineProps<Props>();
  const size = `size-${props.size ?? 5}`;

  // Professional iconist tip:
  // It's very helpful to console log the props here to see what icons
  // are coming through with the wrong combo of collection and/or name.
</script>

<template>
  <svg aria-hidden="true" :class="size" >
    <use :href="`#${[collection, name].filter(Boolean).join('-')}`" />
  </svg>
</template>
