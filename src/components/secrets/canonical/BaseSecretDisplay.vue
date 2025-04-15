<!-- src/components/secrets/canonical/BaseSecretDisplay.vue -->

<script setup lang="ts">

interface Props {}

defineProps<Props>();

</script>

<template>
  <div>
    <slot name="header"></slot>

    <slot name="content"></slot>

    <slot name="warnings"></slot>

    <slot name="cta"></slot>

    <slot name="footer"></slot>
  </div>
</template>
