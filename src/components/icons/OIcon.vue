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
  }
  defineProps<Props>();

  // Professional iconist tip:
  // It's very helpful to console log the props here to see what icons
  // are coming through with the wrong combo of collection and/or name.
</script>

<template>
  <svg aria-hidden="true">
    <use :href="`#${[collection, name].filter(Boolean).join('-')}`" />
  </svg>
</template>
