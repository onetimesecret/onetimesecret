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
</script>

<template>
  <svg aria-hidden="true">
    <use :href="`#${collection}-${name}`" />
  </svg>
</template>
