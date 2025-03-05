<script setup lang="ts">
import Privacy from '@/content/info/privacy.md';
</script>

<template>
  <article class="prose">
    <h1 class="intro dark:text-gray-300">
      {{ $t('privacy-policy') }}
    </h1>

    <Privacy class="prose prose-sm max-w-none dark:prose-invert sm:prose-base lg:prose-lg dark:text-gray-300" />
  </article>
</template>
