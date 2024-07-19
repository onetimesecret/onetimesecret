<template>

    <SecretForm :shrimp="shrimp" :withRecipient="false" :withAsterisk="true" />

</template>

<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';

const shrimp = window.shrimp;

</script>
